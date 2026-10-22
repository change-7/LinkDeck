# 범용 Git Sync 설계

## 목표와 범위

사용자가 등록한 기존 로컬 Git 저장소를 기존 remote/upstream 설정으로 Pull, Push, 양방향 동기화한다. GitHub 및 GitLab을 포함한 일반 Git 인증은 시스템 credential helper와 SSH 설정을 사용한다. FolderSync와 독립 실행하고 선택적으로 전후 연계한다. ChatGPT에서 MCP 시작 후 작업 ID로 완료와 오류를 확인한다.

기존 FolderPair, GitHub 복사 기반 동기화 및 FolderSync MCP의 저장 형식과 동작은 보존한다. 이번 기능은 기존 GitHubSyncService를 이름만 바꾸거나 복사 동작을 재사용하지 않는다. 원격 이벤트 감시, 자동 merge/rebase, 저장소 초기화는 범위 밖이다.

## 구성

- Native/FolderSync/Models에 GitSyncConfiguration, 방향, 단계, 작업 결과 모델을 추가한다. 로컬 경로는 기존 FolderReference/bookmark 방식을 재사용한다. 설정은 별도 저장 키로 보존한다.
- Native/FolderSync/Services에 GitSyncService와 비동기 Git 프로세스 실행을 추가한다. argv로 실행하고 shell 문자열을 조립하지 않는다. UI actor에서 프로세스 종료를 기다리지 않는다.
- GitSyncStore는 설정, 작업 ID, 현재 단계, 실행 기록, 마지막 실행/성공 시각을 관리한다. 앱 시작 시 미완료 기록을 interrupted로 바꾸고 자동 재개하지 않는다.
- FolderPair에 선택적 Git 연계 설정을 추가한다. 기존 JSON에서 누락되면 연계 없음으로 해석한다. 기존 파일 삭제 설정은 유지한다.
- WorkspaceView에 일반 폴더/Git 작업을 구분하는 관리 화면을 추가한다. Git 등록, 수정, 실행, 상세 결과, 기록을 제공한다.
- LinkDeckMCPHandler와 실제 서버 연결에 동일 GitSyncStore를 전달한다. 새로운 도구가 실제 앱에서 같은 작업 상태를 조회한다.

## 저장소 감지와 잠금

git rev-parse로 작업 트리 루트와 gitdir/common-dir을 감지하여 .git 파일을 사용하는 worktree도 처리한다. 저장소가 아니면 등록을 거절하고 init은 실행하지 않는다. 현재 브랜치 upstream의 remote와 원격 브랜치를 우선 사용한다. detached HEAD, upstream 없음, 여러 후보는 안내하고 사용자 선택으로 해결한다. origin/main을 고정하지 않는다.

정규화된 common-dir을 기준으로 저장소 작업을 직렬화한다. 동일 항목과 방향의 중복 시작은 기존 작업 ID를 반환한다. 다른 방향이나 항목의 충돌 요청은 busy를 반환한다. Git lock 또는 merge/rebase 등 진행 중 상태가 있으면 중단한다. 자체 잠금만으로 외부 Git 프로세스를 배제할 수 없으므로 단계 사이 HEAD/index/작업 트리 변경을 검사하고 Git 자체 잠금과 push 거절도 처리한다.

## 실행 정책

Fetch 후 로컬 HEAD와 원격 추적 ref의 ahead/behind를 계산한다. 양쪽 모두 커밋이 있으면 diverged로 중단한다. Pull은 fast-forward만 허용한다. 원격 변경 적용이 필요한데 작업 트리가 dirty면 중단한다. 원격과 같거나 로컬만 앞서 있으면 Pull은 변경 없이 성공한다.

Push는 이미 만든 커밋을 전송한다. 미커밋 변경이 있어도 자동 Commit이 꺼져 있으면 이를 건드리지 않는다. 원격이 앞서 있거나 분기하면 거절한다. push refspec은 감지/선택한 remote와 브랜치를 명시하고 force는 사용하지 않는다.

양방향은 fetch, 이력 검사, 선택적 commit, fast-forward 적용, push, 최종 상태 확인 순서다. 자동 Commit으로 이력이 분기되면 중단하며 생성된 로컬 커밋은 보존한다. 원격 동시 변경은 정상 push 거절로 처리하고 재확인한다. 확인 후에도 원격이 바뀔 수 있으므로 결과에 검증 시점과 ref를 기록한다. 변경이 없으면 commit/push를 생략한다.

## 자동 Commit

기본 비활성화다. 활성화 시 추적 파일의 변경을 기본 대상으로 하고, 새 파일은 명시적 포함 규칙에 허용된 경우만 추가한다. .gitignore 및 포함/제외 glob을 적용하고 삭제도 같은 규칙으로 처리한다. 기존 staged 변경이 있으면 자동 Commit을 중단하여 사용자 index를 보존한다.

후보 파일의 이름과 변경 내용을 검사해 환경변수 파일, 개인 키, 알려진 토큰 패턴과 .obsidian의 인증 관련 설정을 차단한다. 이미 추적된 파일도 검사한다. 민감정보 탐지는 완전성을 보장하지 않으며 차단된 파일은 제외 규칙 또는 수동 검토로 해결한다. 로그와 MCP에는 파일 내용이나 자격증명을 넣지 않는다. 자동 staging/commit 실패 시 자체 변경만 정리하고 사용자의 작업 파일을 되돌리지 않는다.

## FolderSync 연계와 .git 보호

연계는 없음/이전/이후 및 Git 항목 ID, 선택적 방향을 저장한다. 이전 Git 실패 시 폴더 복사를 시작하지 않는다. 이후 Git은 폴더 성공 시만 실행한다. 전체 상태는 모든 단계가 끝난 뒤 완료된다. 독립 Git 작업은 FolderSync를 거치지 않는다.

일반 파일 복사에 .git 제외 옵션을 제공한다. 선택 시 .git 디렉터리와 파일 모두 전송 및 삭제에서 보호한다. 기존 옵션은 마이그레이션으로 임의 변경하지 않는다. 새 항목의 삭제 전파는 기존 기본값 false를 유지한다.

## MCP 계약

- linkdeck_git_sync_list: 등록된 ID, 이름, 저장소 식별명, remote 이름, 브랜치, 방향, 상태. URL에 포함된 자격증명과 전체 로컬 경로는 노출하지 않는다.
- linkdeck_git_sync_start: sync_id와 선택적 direction(pull/push/bidirectional). 작업 ID, 시작 상태, 대상 정보를 즉시 반환한다. 임의 경로/명령은 받지 않는다.
- linkdeck_git_sync_status: job_id 또는 sync_id 하나. 단계, 성공 여부, 각 Git 단계 결과, 커밋/파일 수, 오류 코드와 정제 메시지, 시작/종료 시각을 반환한다.
- linkdeck_git_sync_cancel: job_id. 취소 요청 후 실행 중인 프로세스 종료와 결과 재확인을 기다려 취소 상태를 확정한다. 이미 완료된 commit/push는 되돌리지 않는다.

기존 FolderSync start/list/status 입력과 응답을 유지한다. 연계 항목의 start는 설정한 순서를 실행한다. MCP와 UI 모두 같은 검증과 잠금을 사용한다.

## 오류 및 검증

notRepository, missingRemote, missingUpstream, detachedHead, authenticationFailed, networkFailed, dirtyWorktree, stagedChanges, diverged, repositoryBusy, repositoryChanged, pushRejected, sensitiveFile, cancelled, interrupted, commandFailed를 구분한다. 출력에서 URL 자격증명과 토큰을 제거하고 명령 시간 제한을 둔다.

임시 bare 원격과 복수 clone으로 감지, worktree, 세 방향, no-op, 자동 Commit on/off, staged 보존, 민감 파일, dirty pull, 분기, push 경쟁, 중복 실행, 취소, 실패를 검증한다. 저장소 설정과 작업 기록 재시작, FolderSync 전후 성공/실패, 기존 JSON 호환성, MCP 입력 검증과 도구 등록을 테스트한다. 인증/네트워크 오류는 통제된 실패 실행으로 검증한다. 기존 회귀 테스트와 swift build/test를 실행한다.

실제 LinkDeck 앱 MCP에서 tools/list와 등록된 임시 저장소 start/status를 호출하고 완료 및 로컬 파일 반영을 확인한다. 실제 사용자 저장소는 테스트 대상으로 사용하지 않는다. 실제 연결이 불가능하면 원인과 미검증 항목을 보고하며 통과했다고 주장하지 않는다.

## 현재 작업 트리

GitHubSyncService, LinkDeckMCPHandler 등 관련 파일에 기존 미커밋 변경이 있다. 이 변경을 보존하면서 추가한다. 기존 작업 변경을 되돌리거나 전체 파일을 이전 버전으로 교체하지 않는다.
