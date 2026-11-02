# 휴대폰 동기화 변경 복구 (2026-10-23)

- before-change.tar.gz: 변경 전 Native·Android/app/src·Package.swift·script 소스. API 목록 제거 등 이전 작업도 포함한 실제 작업 파일입니다.
- originals/: 이번에 수정한 기존 파일의 원본.
- restore.patch: 이번 통신 변경만 되돌리고 새 동기화·검증 파일은 제거하는 패치.
- mac-app-before.tar.gz: 변경 전 설치된 맥 LinkDeck.app.
- phone-app-before.apk: 변경 전 휴대폰에서 가져온 APK. 사용자 앱 데이터는 별도로 내보내지 않았습니다.

## 소스 복구

프로젝트 루트에서 실행합니다.

```bash
bash Recovery/remote-sync-2026-10-23/restore.sh --check
bash Recovery/remote-sync-2026-10-23/restore.sh --apply
```

후속 수정으로 검사에 실패하면 적용하지 말고 originals와 비교해 병합하세요.
전체 압축을 현재 소스 위에 덮어쓰지 마세요.

## 설치본 복구

맥 앱을 완전히 종료하고 mac-app-before.tar.gz를 임시 폴더에 푼 뒤, 그 안의 LinkDeck.app으로 /Applications/LinkDeck.app을 교체합니다.
휴대폰은 `adb install -r phone-app-before.apk`로 이전 APK를 다시 설치합니다. 앱을 제거하지 않으면 기존 설정은 유지됩니다.
새 휴대폰은 이전 맥의 전체 상태 메시지도 처리하고, 새 맥은 이전 휴대폰의 전체 상태 형식도 유지하므로 양쪽을 순서대로 복구할 수 있습니다.
