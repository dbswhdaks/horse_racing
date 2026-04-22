import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';

type VerifyRequestBody = {
  productId?: string;
  verificationData?: string;
};

type GoogleTokenResponse = {
  access_token: string;
  token_type: string;
  expires_in: number;
};

type GoogleSubscriptionResponse = {
  subscriptionState?: string;
  lineItems?: Array<{
    productId?: string;
    expiryTime?: string;
  }>;
};

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const GOOGLE_SCOPE = 'https://www.googleapis.com/auth/androidpublisher';

function readEnv(name: string): string {
  const value = Deno.env.get(name)?.trim() ?? '';
  if (value.length === 0) {
    throw new Error(`Missing environment variable: ${name}`);
  }
  return value;
}

function normalizePrivateKey(raw: string): string {
  return raw.replace(/\\n/g, '\n');
}

function toBase64Url(input: Uint8Array | string): string {
  let bytes: Uint8Array;
  if (typeof input === 'string') {
    bytes = new TextEncoder().encode(input);
  } else {
    bytes = input;
  }
  let binary = '';
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
}

function fromBase64Url(base64Url: string): Uint8Array {
  const base64 = base64Url
    .replaceAll('-', '+')
    .replaceAll('_', '/')
    .padEnd(Math.ceil(base64Url.length / 4) * 4, '=');
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const clean = pem
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replaceAll('\n', '')
    .trim();
  const keyData = fromBase64Url(
    clean.replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', ''),
  );
  return crypto.subtle.importKey(
    'pkcs8',
    keyData.buffer,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
}

async function signJwt(
  clientEmail: string,
  privateKeyPem: string,
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: 'RS256', typ: 'JWT' };
  const claimSet = {
    iss: clientEmail,
    scope: GOOGLE_SCOPE,
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  };

  const headerEncoded = toBase64Url(JSON.stringify(header));
  const claimEncoded = toBase64Url(JSON.stringify(claimSet));
  const unsignedToken = `${headerEncoded}.${claimEncoded}`;
  const privateKey = await importPrivateKey(privateKeyPem);
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    privateKey,
    new TextEncoder().encode(unsignedToken),
  );
  return `${unsignedToken}.${toBase64Url(new Uint8Array(signature))}`;
}

async function getGoogleAccessToken(
  clientEmail: string,
  privateKeyPem: string,
): Promise<string> {
  const assertion = await signJwt(clientEmail, privateKeyPem);
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Google OAuth token request failed: ${response.status} ${text}`);
  }
  const tokenData = (await response.json()) as GoogleTokenResponse;
  if (!tokenData.access_token) {
    throw new Error('Google OAuth token response does not include access_token');
  }
  return tokenData.access_token;
}

function parseActiveState(subscriptionState: string | undefined): boolean {
  if (!subscriptionState) return false;
  return (
    subscriptionState === 'SUBSCRIPTION_STATE_ACTIVE' ||
    subscriptionState === 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD'
  );
}

function maxExpiryTime(lineItems: GoogleSubscriptionResponse['lineItems']): string | null {
  if (!lineItems || lineItems.length === 0) return null;
  let latest: Date | null = null;
  for (const item of lineItems) {
    if (!item.expiryTime) continue;
    const dt = new Date(item.expiryTime);
    if (Number.isNaN(dt.getTime())) continue;
    if (latest === null || dt > latest) latest = dt;
  }
  return latest ? latest.toISOString() : null;
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS });
  }
  if (req.method !== 'POST') {
    return new Response(
      JSON.stringify({ isValid: false, isActive: false, message: 'Method not allowed' }),
      {
        status: 405,
        headers: { ...CORS_HEADERS, 'content-type': 'application/json' },
      },
    );
  }

  try {
    const body = (await req.json()) as VerifyRequestBody;
    const purchaseToken = body.verificationData?.trim() ?? '';
    const requestProductId = body.productId?.trim() ?? '';
    if (!purchaseToken || !requestProductId) {
      return new Response(
        JSON.stringify({
          isValid: false,
          isActive: false,
          message: 'verificationData(product token) and productId are required',
        }),
        {
          status: 400,
          headers: { ...CORS_HEADERS, 'content-type': 'application/json' },
        },
      );
    }

    const packageName = readEnv('ANDROID_PACKAGE_NAME');
    const serviceAccountEmail = readEnv('GOOGLE_SERVICE_ACCOUNT_EMAIL');
    const serviceAccountPrivateKey = normalizePrivateKey(
      readEnv('GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY'),
    );
    const accessToken = await getGoogleAccessToken(
      serviceAccountEmail,
      serviceAccountPrivateKey,
    );

    const verifyUrl =
      `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/` +
      `${encodeURIComponent(packageName)}/purchases/subscriptionsv2/tokens/` +
      `${encodeURIComponent(purchaseToken)}`;
    const verifyResponse = await fetch(verifyUrl, {
      method: 'GET',
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    if (!verifyResponse.ok) {
      const text = await verifyResponse.text();
      return new Response(
        JSON.stringify({
          isValid: false,
          isActive: false,
          message: `Google verify failed: ${verifyResponse.status}`,
          details: text,
        }),
        {
          status: 200,
          headers: { ...CORS_HEADERS, 'content-type': 'application/json' },
        },
      );
    }

    const payload = (await verifyResponse.json()) as GoogleSubscriptionResponse;
    const matchedLineItem = payload.lineItems?.find((item) => item.productId === requestProductId);
    const isProductMatched = !!matchedLineItem;
    const isActiveByState = parseActiveState(payload.subscriptionState);
    const expiresAt = maxExpiryTime(payload.lineItems ?? []);
    const isActiveByTime = expiresAt ? new Date(expiresAt) > new Date() : false;
    const isValid = isProductMatched;
    const isActive = isValid && isActiveByState && isActiveByTime;

    return new Response(
      JSON.stringify({
        isValid,
        isActive,
        expiresAt,
        productMatched: isProductMatched,
        subscriptionState: payload.subscriptionState ?? null,
        message: isValid ? 'ok' : 'productId mismatch',
      }),
      {
        status: 200,
        headers: { ...CORS_HEADERS, 'content-type': 'application/json' },
      },
    );
  } catch (error) {
    return new Response(
      JSON.stringify({
        isValid: false,
        isActive: false,
        message: error instanceof Error ? error.message : String(error),
      }),
      {
        status: 500,
        headers: { ...CORS_HEADERS, 'content-type': 'application/json' },
      },
    );
  }
});
