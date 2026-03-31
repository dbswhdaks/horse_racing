fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## Android

### android build

```sh
[bundle exec] fastlane android build
```

Flutter AAB 빌드

### android internal

```sh
[bundle exec] fastlane android internal
```

내부 테스트 트랙에 배포

### android beta

```sh
[bundle exec] fastlane android beta
```

베타(오픈 테스트) 트랙에 배포

### android production

```sh
[bundle exec] fastlane android production
```

프로덕션 배포

### android check_version

```sh
[bundle exec] fastlane android check_version
```

현재 버전 코드 확인 (Play Store)

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
