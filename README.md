# LinkDeck

Mac과 Android 휴대폰에서 버튼을 실행하고 Codex 상태를 확인하는 앱입니다. Novation Launchpad Mini MK1도 지원합니다.

## 빌드·실행

```bash
./script/build_and_run.sh --verify
```

완성 앱은 프로젝트 최상단의 `LinkDeck.app`입니다.

## 구성

- `Native/`: SwiftUI 앱, CoreMIDI 연결, 버튼 매핑과 LED 모션
- `script/`: 빌드·앱 번들·아이콘 생성 스크립트
- `assets/`: 앱 아이콘

앱 실행·macOS 단축키 실행에는 손쉬운 사용 권한이 필요할 수 있습니다.

## ChatGPT에서 LinkDeck 제어

Mac 앱 설정의 **ChatGPT 연결**에서 OpenAI Secure MCP Tunnel을 연결합니다.
ChatGPT는 `linkdeck_list_buttons`로 등록된 버튼을 조회하고,
`linkdeck_press_button`으로 그 버튼의 저장된 동작을 실행할 수 있습니다.
`linkdeck_get_sleep_status`로 Mac의 실제 `caffeinate` 잠자기 방지 상태도 조회합니다.
“지금 불면증과 숙면 중 어떤 상태야?”라고 질문하면 됩니다. 불면증은 잠자기 방지가 켜진 상태,
숙면은 해당 잠자기 방지가 꺼진 상태이며 Mac이 실제로 잠들었다는 뜻은 아닙니다.
스마트폰 상단바에도 같은 상태를 1초마다 갱신하며 연결되지 않았거나 조회할 수 없으면 상태 미확인으로 표시합니다.
Mac 버튼과 스마트폰 버튼의 짧게·길게 누르기, 폴더 안의 버튼을 지원합니다.
임의 명령어를 전달하는 도구는 제공하지 않으며, 목록에는 명령어·클립보드 내용이 포함되지 않습니다.

1. `brew install openai/tools/tunnel-client`로 공식 터널 클라이언트를 설치합니다.
2. [OpenAI 터널 관리](https://platform.openai.com/settings/organization/tunnels)에서 터널을 준비합니다.
3. Tunnels Read·Use 권한이 있는 [런타임 API 키](https://platform.openai.com/settings/organization/api-keys)를 발급합니다.
4. Mac 앱의 **ChatGPT 연결**에 터널 ID와 키를 입력하고 **터널 연결**을 누릅니다.
5. 준비 완료 상태가 표시되면 [ChatGPT 앱 설정](https://chatgpt.com/#settings/Connectors)의 개발자 모드에서 앱을 만들고 해당 터널을 선택합니다. MCP 인증은 ‘없음’을 선택합니다. OpenAI 터널의 계정·조직 접근 권한은 별도로 적용됩니다.
6. ChatGPT에 “LinkDeck 버튼 목록 보여줘”, “LinkDeck의 잠자기 방지 버튼 실행해줘”처럼 요청합니다.

키는 앱 실행 중 메모리와 터널 프로세스의 환경변수에만 보관합니다.
터널 ID만 저장하며, 앱 재시작 후에는 키를 다시 입력해야 합니다.
연결은 기본적으로 꺼져 있습니다. 연결 해제나 앱 종료 시 로컬 서버와 터널 프로세스를 중단합니다.
창을 닫아 메뉴 막대에 남긴 경우에는 연결을 유지합니다.
MCP 서버는 임시 포트의 `127.0.0.1`에만 바인딩하고, 세션마다 생성한 로컬 인증 토큰을 요구합니다.
공개 포트·공개 Cloudflare 터널을 만들지 않습니다.

OpenAI 터널 권한과 ChatGPT 개발자 모드 사용 가능 여부는 계정·조직 설정에 따라 다릅니다.
구체적인 연결 절차는 [OpenAI 공식 안내](https://developers.openai.com/api/docs/guides/secure-mcp-tunnels)를 확인하세요.
