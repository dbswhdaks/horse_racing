#!/usr/bin/env bash
# ============================================================
# 경마 Plus 배포 스크립트
# 사용법: bash script.sh
# ============================================================

set -u

FIREBASE_PROJECT="horse-racing-bb0ef"
HOSTING_URL="https://horse-racing-bb0ef.web.app"
PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_ROOT"

CURRENT_VERSION=$(grep '^version:' pubspec.yaml | sed 's/version:[[:space:]]*//' | tr -d '\r')

# ─────────────────────────────────────────────
# 헬퍼
# ─────────────────────────────────────────────
log() { echo; echo "▶ $1"; }
ok()  { echo "✅ $1"; }
err() { echo "❌ $1" >&2; }

# Firebase Hosting 배포 (firebase-tools 일시 오류 시 캐시 정리 후 1회 재시도)
deploy_hosting() {
    firebase use "$FIREBASE_PROJECT" >/dev/null
    if firebase deploy --only hosting --non-interactive; then return 0; fi
    echo "⚠️  배포 실패 — .firebase 캐시 정리 후 재시도"
    rm -rf .firebase
    firebase deploy --only hosting --non-interactive
}

# 결과물이 위치한 폴더를 OS 에 맞는 방식으로 연다.
#   - Windows(MINGW64/Git Bash): explorer.exe
#   - macOS                    : open
#   - Linux                    : xdg-open
open_folder() {
    local target="$1"
    [ -d "$target" ] || return 0
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*)  explorer.exe "$(cygpath -w "$target")" 2>/dev/null || true ;;
        Darwin)                open "$target" 2>/dev/null || true ;;
        Linux)                 xdg-open "$target" 2>/dev/null || true ;;
    esac
}

# pubspec.yaml 의 version 한 단계 올리기 (예: 1.0.25+25 → 1.0.26+26)
bump_version() {
    local line name_part build_part major minor patch new_patch new_build new_version
    line=$(grep '^version:' pubspec.yaml)
    name_part=$(echo "$line" | sed -E 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+).*/\1/')
    build_part=$(echo "$line" | sed -E 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+).*/\2/')
    major=$(echo "$name_part" | cut -d. -f1)
    minor=$(echo "$name_part" | cut -d. -f2)
    patch=$(echo "$name_part" | cut -d. -f3)
    new_patch=$((patch + 1))
    new_build=$((build_part + 1))
    new_version="${major}.${minor}.${new_patch}+${new_build}"
    awk -v new="version: ${new_version}" '/^version:/ { print new; next } { print }' \
        pubspec.yaml > pubspec.yaml.tmp && mv pubspec.yaml.tmp pubspec.yaml
    ok "버전 변경: ${name_part}+${build_part}  →  ${new_version}"
}

# ─────────────────────────────────────────────
# 메뉴
# ─────────────────────────────────────────────
clear 2>/dev/null || true
echo "============================================"
echo "   경마 Plus 배포 스크립트"
echo "   현재 버전 : $CURRENT_VERSION"
echo "============================================"
echo
echo "  [1] GitHub 자동 업로드   (add → commit → push)"
echo "  [2] Firebase 자동 업로드 (웹 빌드 + Hosting 배포)"
echo "  [3] 앱 빌드             (버전업 + AAB 빌드 + 폴더 열기)"
echo "  [q] 종료"
echo
read -p "Run: " selection

case "$selection" in

    1)
        log "GitHub 자동 업로드"

        # 변경 사항이 전혀 없으면 그대로 종료
        if [ -z "$(git status --porcelain)" ]; then
            ok "커밋할 변경사항이 없습니다."
            exit 0
        fi

        # 변경 요약을 보여준다 (어떤 파일이 올라갈지 사용자가 확인)
        echo
        echo "── 변경된 파일 ──"
        git status --short
        echo

        # 커밋 메시지 입력. 그냥 엔터 치면 타임스탬프로 자동 생성.
        DEFAULT_MSG="chore: auto commit $(date +%Y-%m-%d_%H:%M:%S)"
        read -p "커밋 메시지 (엔터 = '${DEFAULT_MSG}'): " COMMIT_MSG
        COMMIT_MSG="${COMMIT_MSG:-$DEFAULT_MSG}"

        BRANCH=$(git rev-parse --abbrev-ref HEAD)

        git add -A
        git commit -m "$COMMIT_MSG"
        # 현재 체크아웃된 브랜치 그대로 푸시. force 옵션은 사용하지 않는다.
        git push origin "$BRANCH"

        ok "GitHub 업로드 완료 (branch: ${BRANCH})"
        ;;

    2)
        log "Firebase 자동 업로드 (웹 빌드 + Hosting 배포)"
        flutter pub get
        # --no-web-resources-cdn : CanvasKit/Skwasm 등 엔진 리소스를 gstatic CDN
        #   대신 로컬 번들에 포함시켜 iOS Safari 등에서 CDN 차단/지연 시에도
        #   안정적으로 첫 프레임이 그려지도록 한다.
        # --no-tree-shake-icons : MaterialIcons / CupertinoIcons 의 글리프
        #   트리쉐이킹을 비활성화한다. tree-shake 된 폰트는 iOS Safari
        #   (CanvasKit) 에서 디코딩 실패로 아이콘이 □ 로 깨져 보이거나,
        #   동적으로 IconData 를 만드는 코드에서 글리프가 누락될 수 있다.
        flutter build web --release \
            --pwa-strategy=none \
            --no-web-resources-cdn \
            --no-tree-shake-icons

        # 빌드된 index.html 의 BUILD_TAG_PLACEHOLDER 를 실제 타임스탬프로 치환.
        # 로딩 화면 하단에 'build YYYYMMDD-HHMMSS' 가 노출되어 모바일 Safari 가
        # 새 빌드를 정상적으로 받았는지 즉시 확인할 수 있다.
        BUILD_TAG="$(date +%Y%m%d-%H%M%S)"
        if [ -f build/web/index.html ]; then
            sed "s/BUILD_TAG_PLACEHOLDER/${BUILD_TAG}/g" build/web/index.html \
                > build/web/index.html.tmp && \
                mv build/web/index.html.tmp build/web/index.html
            echo "▶ build tag injected: ${BUILD_TAG}"
        fi

        deploy_hosting
        ok "배포 완료 → ${HOSTING_URL}  (build ${BUILD_TAG})"
        ;;

    3)
        log "앱 빌드 (버전업 + AAB)"

        # 1) 버전 자동 증가 — Play Console 은 동일 버전코드 재업로드를 거부한다.
        bump_version
        NEW_VERSION=$(grep '^version:' pubspec.yaml | sed 's/version:[[:space:]]*//' | tr -d '\r')

        # 2) 의존성 동기화 후 릴리즈 AAB 빌드
        flutter pub get
        flutter build appbundle --release

        AAB_DIR="build/app/outputs/bundle/release"
        AAB_PATH="${AAB_DIR}/app-release.aab"

        if [ ! -f "$AAB_PATH" ]; then
            err "AAB 파일을 찾지 못했습니다: ${AAB_PATH}"
            exit 1
        fi

        # 3) 빌드 산출물 폴더를 OS 탐색기로 열어준다.
        open_folder "$AAB_DIR"

        echo
        ok "AAB 빌드 완료 (version ${NEW_VERSION})"
        echo "   파일: ${AAB_PATH}"
        echo
        echo "다음 단계 — Play Console 업로드:"
        echo "  1) https://play.google.com/console 접속"
        echo "  2) [경마 Plus] → [프로덕션] → [새 버전 만들기]"
        echo "  3) 위에서 열린 폴더의 app-release.aab 를 드래그하여 업로드"
        echo "  4) 변경사항 작성 후 [출시 검토 시작]"
        ;;

    q|Q|"")
        echo "종료합니다."
        ;;

    *)
        err "알 수 없는 명령: ${selection}"
        exit 1
        ;;

esac
