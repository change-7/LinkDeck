# LinkDeck

Mac과 Android 휴대폰에서 버튼을 실행하고 Codex 상태를 확인하는 앱입니다. 물리 런치패드와 메뉴바 LED 애니메이션 기능은 제거했습니다.

## 빌드·실행

```bash
./script/build_and_run.sh --verify
```

완성 앱은 프로젝트 최상단의 `LinkDeck.app`입니다.

## 구성

- `Native/`: SwiftUI 앱, 휴대폰 버튼 편집·원격 실행과 API 연결
- `Recovery/launchpad-2026-10-22/`: 런치패드 원본 코드와 복구 패치·안내
- `script/`: 빌드·앱 번들·아이콘 생성 스크립트
- `assets/`: 앱 아이콘

앱 실행·macOS 단축키 실행에는 손쉬운 사용 권한이 필요할 수 있습니다.

## ChatGPT에서 LinkDeck 제어

### Stable Whisper 전사와 번역

Stable Whisper 앱이 설치되어 있으면 LinkDeck은 실행 파일을 `--mcp`로 실행하고
위스퍼의 MCP 도구 6개를 `linkdeck_whisper_` 접두사로 제공합니다.
별도의 위스퍼 터널이나 실행 버튼 등록은 필요하지 않습니다. 위스퍼에서 엔진 설치는 먼저 완료해야 합니다.
입력 규격은 설치된 위스퍼의 도구 목록을 그대로 사용하므로 해당 버전이 지원하는 YouTube URL과
Mac 로컬 음성·영상 파일의 절대 경로를 전달할 수 있습니다.

예: “링크덱으로 `/Users/pdg/Movies/interview.mp4`를 전사하고 한국어로 번역해줘.”

ChatGPT는 전사 시작 도구의 작업 ID로 상태를 확인하고 완료 후 자막을 페이지별로 조회합니다.
번역문을 자막 번호별로 저장하면 위스퍼가 원래 타임코드를 유지한 SRT를 생성합니다.
로컬 경로는 다운로드 링크가 아니며 ChatGPT 첨부 파일은 Mac으로 자동 전달되지 않습니다.
긴 작업은 나중에 같은 작업 ID로 상태를 다시 물어봐야 할 수 있습니다.

LinkDeck은 연결 중 위스퍼 MCP 프로세스를 유지하고 연결 해제 시 종료합니다.
기존 위스퍼 터널과의 저장 폴더 잠금 충돌을 피하기 위해
`~/Library/Application Support/Stable Whisper/linkdeck-mcp-jobs/`에 별도로 작업을 보관합니다.
연결을 종료하면 진행 중 작업이 중단될 수 있으며 재연결 후 작업 목록과 상태를 확인하세요.

### 연결 설정

Mac 앱 설정의 **ChatGPT 연결**에서 OpenAI Secure MCP Tunnel을 연결합니다.
ChatGPT는 `linkdeck_list_buttons`로 등록된 버튼을 조회하고,
`linkdeck_press_button`으로 그 버튼의 저장된 동작을 실행할 수 있습니다.
기존 앱 버튼에서 **플러그인에서 종료 허용**을 체크하면,
`linkdeck_list_buttons`의 `can_quit_app`이 `true`인 버튼 ID를 `linkdeck_quit_app`의 `button_id`로 전달해 해당 앱의 일반 종료를 요청할 수 있습니다.
기본값은 꺼짐이며, 별도의 종료 버튼이나 대상 앱 선택은 필요하지 않습니다. 체크를 해제하거나 버튼을 지우면 종료 요청을 거부합니다.
저장하지 않은 문서가 있으면 Mac에서 저장 확인이 필요할 수 있습니다. 강제 종료는 지원하지 않습니다.
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

연결할 때 API 키를 macOS 키체인에 저장하고 입력칸을 비웁니다. 키를 비워 두면 저장된 키를 사용합니다.
터널 ID와 자동 연결 설정도 저장합니다. 앱 시작 시 자동 연결이 켜져 있으면 재시작·재설치 후 같은 터널로 연결합니다.
연결 해제를 누르면 자동 연결도 꺼집니다. 앱 종료는 자동 연결 설정을 유지하며 로컬 서버와 터널 프로세스만 중단합니다.
저장된 API 키 삭제는 연결 해제 후 사용할 수 있습니다. 재빌드할 때 앱의 번들 ID와 코드 서명 요구사항을 유지해야 합니다.
창을 닫아 메뉴 막대에 남긴 경우에는 연결을 유지합니다.
MCP 서버는 임시 포트의 `127.0.0.1`에만 바인딩하고, 세션마다 생성한 로컬 인증 토큰을 요구합니다.
공개 포트·공개 Cloudflare 터널을 만들지 않습니다.

OpenAI 터널 권한과 ChatGPT 개발자 모드 사용 가능 여부는 계정·조직 설정에 따라 다릅니다.
구체적인 연결 절차는 [OpenAI 공식 안내](https://developers.openai.com/api/docs/guides/secure-mcp-tunnels)를 확인하세요.
