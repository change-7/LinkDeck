# 런치패드 기능 복구 보관본 (2026-10-22)

물리 Launchpad Mini MIDI 입력·LED 출력·모션·가상 미리보기·LED 말풍선과 메뉴바 애니메이션을 제거하기 **직전의 실제 작업 파일**입니다. 당시 미커밋 변경도 포함합니다.

## 구성

- `originals/`: 이번에 수정하거나 제거한 파일의 원본. 원래 경로 구조로 보관합니다.
- `before-removal.tar.gz`: 제거 직전 Native, Tests, Package.swift, script의 전체 스냅샷. README 원본은 originals/README.md에 별도 보관합니다.
- `installed-before.tar.gz`: 교체 전 설치된 LinkDeck.app 원본.
- `VALIDATION.md`: 테스트·실행·휴대폰 설정 보존·복구 검증 결과와 확인 범위.
- `restore.patch`: 이번 제거 변경만 되돌리는 패치. 이후 다른 기능의 변경을 통째로 덮어쓰지 않도록 문맥을 확인합니다.
- `restore.sh`: 기본은 복구 가능 여부 확인만 수행합니다.

## 복구

프로젝트 루트에서:

```bash
bash Recovery/launchpad-2026-10-22/restore.sh --check
bash Recovery/launchpad-2026-10-22/restore.sh --apply
swift test
./script/build_and_run.sh --package
```

그 후 새로 만든 LinkDeck.app을 실행하세요. /Applications의 설치본은 자동으로 교체되지 않습니다.

후속 변경으로 패치 검사에 실패하면 적용을 중단하고 originals와 비교해 해당 부분만 병합하세요. 전체 스냅샷을 현재 프로젝트 위에 무조건 풀지 마세요. `--apply` 실행 전 현재 작업도 별도로 보관하세요.

## 보존 범위

휴대폰 버튼·폴더·길게 누르기·A/B 동작·원격 실행, 휴대폰 스킨·사운드·마이크, Codex 원격 상태·승인, API 서버·터널은 유지합니다.
공용 PadAction·버튼·백업 모델과 예전 런치패드 설정 데이터는 호환성과 복구를 위해 유지합니다. MIDI 클라이언트와 런치패드 모션 타이머는 생성되지 않습니다.
사용자 설정이나 키체인 비밀값은 이 소스 보관본에 별도로 내보내지 않았습니다.
