echo "자동화 스크립트 목록입니다."
echo
echo "[1] CodegenLoader 생성"
echo "[2] LocaleKeys 생성"
echo "[3] 프로젝트 빌드"
echo "[4] 프로젝트 웹호스팅"
echo "[5] 디버그 설치 (기존 앱 삭제 후)"
echo
read -p "Run: " selection

case $selection in

    1)
    echo "CodegenLoader 생성"
    flutter pub run easy_localization:generate -S assets/translations
    ;;

    2)
    echo "LocaleKeys 생성"
    flutter pub run easy_localization:generate -f keys -o locale_keys.g.dart -S assets/translations
    ;;

    3)
    echo "프로젝트 빌드"
    flutter build appbundle
    ;;

    4)
    echo "프로젝트 웹호스팅"
    flutter build web
    firebase deploy --only hosting
    ;;

    5)
    echo "기존 앱 삭제 후 디버그 설치"
    adb uninstall com.happy.kdrive
    flutter install
    ;;

    *)
    echo "Unknown command!!"
    ;;

esac