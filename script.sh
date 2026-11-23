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

current_version() {
    grep '^version:' pubspec.yaml | sed 's/version:[[:space:]]*//' | tr -d '\r'
}

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
    build_part=$(echo "$line" | sed -E 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+).*/\2/' | tr -d '\r')
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
# 작업
# ─────────────────────────────────────────────

# $1 이 주어지면 커밋 메시지를 묻지 않고 그대로 쓴다.
github_upload() {
    log "GitHub 자동 업로드"

    # 변경 사항이 전혀 없으면 그대로 종료
    if [ -z "$(git status --porcelain)" ]; then
        ok "커밋할 변경사항이 없습니다."
        return 0
    fi

    # 변경 요약을 보여준다 (어떤 파일이 올라갈지 사용자가 확인)
    echo
    echo "── 변경된 파일 ──"
    git status --short
    echo

    local commit_msg="${1:-}"
    if [ -z "$commit_msg" ]; then
        # 그냥 엔터 치면 타임스탬프로 자동 생성.
        local default_msg="chore: auto commit $(date +%Y-%m-%d_%H:%M:%S)"
        read -p "커밋 메시지 (엔터 = '${default_msg}'): " commit_msg
        commit_msg="${commit_msg:-$default_msg}"
    fi

    local branch
    branch=$(git rev-parse --abbrev-ref HEAD)

    git add -A
    git commit -m "$commit_msg" || return 1
    # 현재 체크아웃된 브랜치 그대로 푸시. force 옵션은 사용하지 않는다.
    git push origin "$branch" || return 1

    ok "GitHub 업로드 완료 (branch: ${branch})"
}

firebase_upload() {
    log "Firebase 자동 업로드 (웹 빌드 + Hosting 배포)"
    flutter pub get || return 1
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
        --no-tree-shake-icons || return 1

    # 빌드된 index.html 의 BUILD_TAG_PLACEHOLDER 를 실제 타임스탬프로 치환.
    # 로딩 화면 하단에 'build YYYYMMDD-HHMMSS' 가 노출되어 모바일 Safari 가
    # 새 빌드를 정상적으로 받았는지 즉시 확인할 수 있다.
    local build_tag
    build_tag="$(date +%Y%m%d-%H%M%S)"
    if [ -f build/web/index.html ]; then
        sed "s/BUILD_TAG_PLACEHOLDER/${build_tag}/g" build/web/index.html \
            > build/web/index.html.tmp && \
            mv build/web/index.html.tmp build/web/index.html
        echo "▶ build tag injected: ${build_tag}"
    fi

    deploy_hosting || return 1
    ok "배포 완료 → ${HOSTING_URL}  (build ${build_tag})"
}

app_build() {
    log "앱 빌드 (버전업 + AAB)"

    # 1) 버전 자동 증가 — Play Console 은 동일 버전코드 재업로드를 거부한다.
    bump_version
    local new_version
    new_version=$(current_version)

    # 2) 의존성 동기화 후 릴리즈 AAB 빌드
    flutter pub get || return 1
    flutter build appbundle --release || return 1

    local aab_dir="build/app/outputs/bundle/release"
    local aab_path="${aab_dir}/app-release.aab"

    if [ ! -f "$aab_path" ]; then
        err "AAB 파일을 찾지 못했습니다: ${aab_path}"
        return 1
    fi

    # 3) 빌드 산출물 폴더를 OS 탐색기로 열어준다.
    open_folder "$aab_dir"

    echo
    ok "AAB 빌드 완료 (version ${new_version})"
    echo "   파일: ${aab_path}"
    echo
    echo "다음 단계 — Play Console 업로드:"
    echo "  1) https://play.google.com/console 접속"
    echo "  2) [경마 Plus] → [프로덕션] → [새 버전 만들기]"
    echo "  3) 위에서 열린 폴더의 app-release.aab 를 드래그하여 업로드"
    echo "  4) 변경사항 작성 후 [출시 검토 시작]"
}

# 앱 빌드에서 올린 버전이 웹에도 들어가고, 마지막에 그 버전 변경을 커밋하도록
# 앱 빌드 → 웹 배포 → GitHub 순서로 실행한다. 중간에 실패하면 멈춘다.
run_all() {
    app_build || { err "앱 빌드 실패 — 이후 단계를 건너뜁니다."; return 1; }
    firebase_upload || { err "Firebase 배포 실패 — GitHub 업로드를 건너뜁니다."; return 1; }
    github_upload "chore: release $(current_version)" || { err "GitHub 업로드 실패"; return 1; }
    echo
    ok "전체 완료 (version $(current_version))"
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
echo "  [4] 전체 실행           (3 → 2 → 1 순서)"
echo "  [q] 종료"
echo
read -p "Run: " selection

case "$selection" in
    1) github_upload || exit 1 ;;
    2) firebase_upload || exit 1 ;;
    3) app_build || exit 1 ;;
    4) run_all || exit 1 ;;
    q|Q|"") echo "종료합니다." ;;
    *)
        err "알 수 없는 명령: ${selection}"
        exit 1
        ;;
esac
