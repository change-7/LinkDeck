# 검증 결과 (2026-10-22)

- Swift 회귀 테스트: 88개 통과, 실패 0개. CodexConnectionViewTests, CodexActivityIntegrationTests, CodexRemoteStateTests, SmartphoneFolderEditorTests, LaunchpadBackupTests, LinkDeckMCPTests, AppAPIManifestTests, AppAPIIdleTests.
- 앱 패키징: `./script/build_and_run.sh --package` 성공.
- 코드 서명: 프로젝트 번들 및 설치 실행 파일 검증 성공.
- /Applications/LinkDeck.app 교체 및 재실행 완료.
- 실행 중인 Mac UI에서 API 앱 목록 및 휴대폰 버튼 편집 화면 확인. 탐색 메뉴에 휴대폰·API 앱만 표시됨. 짧게/길게 누르기, A/B 전환, 버튼 라벨과 URL 입력 필드 표시 확인.
- 로컬 TCP 브리지 hello/state, 부작용 없는 more 명령, 존재하지 않는 휴대폰 버튼 요청의 거부 확인.
- 교체 전후 휴대폰 3페이지·48개 버튼의 전송 데이터 SHA-256 일치:
  `f9fc1ba5dd12103faec55b4e0b2c814829126363d6c6378f0d7994adba928347`
- Codex 연결 true, 실제 USB ADB 휴대폰의 TCP 43123 재연결 확인.
- 외부 LinkDeck MCP list_buttons 호출 성공.
- 제거한 MIDI 관리자·가상 모션 플레이어·메뉴바 애니메이션·LED 말풍선의 심볼이 새 실행 파일에 없는 것을 확인.
- 최종 복구 패치를 별도 임시 프로젝트에 실제 적용 후 changed-files.txt의 모든 파일을 originals와 cmp 비교: 모두 일치.
- restore.sh 기본 dry-run, 잘못된 인수 거부, bash 문법 검사 통과.
- git diff --check 통과.

## 한계

실제 휴대폰에서 저장된 버튼을 눌러 앱 실행이나 단축키를 발생시키는 검사는 하지 않았습니다. Mac 설정 창 추가 UI 확인은 CUA native pipe 오류로 중단되었고, 설정 탭 목록은 자동 테스트로 확인했습니다. 장시간 CPU·배터리 절감량은 측정하지 않았습니다. Swift LSP 진단 대기 시간 초과가 있었지만 이후 Swift 컴파일과 위 테스트는 통과했습니다.

## 설치본 복구

installed-before.tar.gz에는 교체 전 /Applications/LinkDeck.app이 들어 있습니다. 기존 설치본으로 즉시 되돌려야 하면 LinkDeck을 완전히 종료한 뒤 이 압축 파일을 임시 폴더에 풀고 그 안의 LinkDeck.app으로 설치본을 교체하세요. 소스 기능 복구는 README.md의 restore.sh 절차를 사용하세요.
