# macOS 주기적 디스크 청소

2026-09-29 용량 조사·수동 정리 후 같은 데이터가 다시 쌓이지 않도록 등록했다.
`com.owen.disk-cleanup` LaunchAgent가 매일 **04:30, 머신 현지 시각**에 실행한다.
사용자 로그인 세션에서 실행하며 잠자기 중 놓친 시각은 macOS launchd가 기상 후 처리한다.
기존 `com.owen.chrome-automation-gc`의 시간별 임시 브라우저 프로필 청소는 별도로 유지한다.

| 대상 | 보존 기간 | 보호 조건 |
|---|---:|---|
| CapCut·npm·Chrome·Slack·Claude 캐시, 앱 업데이트 설치 파일 | 3일 | 최신 mtime/ctime, 열린 파일, 소유 앱 프로세스 |
| npx 패키지, 개발 검증/배포 복제 폴더, `/private/tmp/studio-sandbox/app/.next` | 7일 | 하위 전체 최신 수정·프로세스 명령줄·열린 파일 |
| `/private/tmp/claude-<uid>` 세션 scratchpad와 bash-edit-diff | 7일 | 세션 디렉터리 전체 유휴 기준 |
| Finder TemporaryItems 영상 파일 | 7일 | MP4/MOV/M4V/AVI/MKV만; PNG·문서 제외 |
| Claude·Codex 구버전 | 7일 | current 링크 버전 및 실제 로드된 버전 보존; 링크 불명확 시 전체 보존 |
| Claude VM 번들 | 14일 | Claude 앱·VM 프로세스 및 열린 이미지 보호; 이미지 atime도 확인 |
| 휴지통 항목 | 30일 | **첫 자동 관측 이후** 30일 + 하위 파일 최신 수정 확인 |

3일·7일은 날짜 이름이 아니라 파일 메타데이터 기준이다. 임시 작업과 빌드 폴더는
그 아래 새 파일이 하나라도 있으면 통째로 보존한다. 캐시는 오래된 파일을 선별한다.
휴지통으로 방금 옮긴 오래된 파일이 즉시 삭제되지 않도록 첫 관측 시각을 별도로 기록한다.

프로세스/열린 파일 조회 실패 시 삭제를 중단한다. 30초가 넘는 실행은 프로세스 목록을
갱신하며, 삭제 직전 경로·inode·mtime/ctime을 재확인한다. 조상 심링크를 따라가지 않고,
하위 마운트·열린 하드링크·소켓·특수 파일도 보존한다. 앱 시작과 검사 사이의 순간적인
경쟁까지 완전히 제거하는 것은 아니므로 실제 삭제 범위는 명시된 재생성/임시 경로에 한정한다.

프로젝트·원본 영상·Google Drive·대화 기록·Hermes data/wiki/DB·활성 Codex 런타임은
자동 정리 대상이 아니다. Chrome code_sign_clone도 이번 정책에 포함하지 않는다.
Logi 시스템 캐시는 사용자에게 쓰기 권한이 있을 때만 정리하며, 없으면 #ops에 보존 사유를
표시한다. 자동 sudo·암호 저장·앱 강제 종료는 하지 않는다.

## Slack

- 채널: `#ops` (`C0C4SVD21K4`, nioh 워크스페이스).
- 설정: `~/.config/disk-cleanup/config.json`.
- 발송: `~/.hermes/profiles/cs/scripts/slack_post.py`.
- 인증: 위 helper가 CS `.env`의 `SLACK_BOT_TOKEN`을 읽는다. 토큰을 dotfiles·plist·로그에 복사하지 않는다.
- 각 실행의 삭제 그룹, 관측 삭제량, 실제 여유 공간 전후, 보존 사유, 오류를 알린다.
- 실패 시 `pending-slack.json`에 최대 30회분을 보관하고 다음 실행에 같은 delivery ID로 재시도한다.
- CS 알림 게이트 설정을 그대로 따른다. 2026-09-29 현재 CS 게이트는 해제 상태다.
- Slack 전송은 공식 [`chat.postMessage`](https://docs.slack.dev/reference/methods/chat.postMessage/)를 쓰는 기존 helper에 위임한다.

## 확인·중지

```bash
~/.local/bin/disk-cleanup --dry-run
~/.local/bin/disk-cleanup --apply --notify
launchctl print gui/$(id -u)/com.owen.disk-cleanup
launchctl bootout gui/$(id -u)/com.owen.disk-cleanup
```

영구 중지는 plist 배포/등록을 source에서 제거하거나 LaunchAgent를 disable하고 등록 스크립트가
다시 실행되지 않도록 관리한다. `run_onchange_after_10-disk-cleanup.sh.tmpl`은 파일 배포가 끝난
after 단계에 등록한다. 최초 설치 및 변경 적용 자체는 청소를 즉시 실행하지 않는다.
Linux에는 LaunchAgent를 배포하지 않고 Python 실행도 macOS 여부를 확인한다.
CS의 `.env`/발송 helper가 없는 머신은 자동 등록하지 않는다.

상태는 `~/.local/state/disk-cleanup/`에 저장한다:

- `last-run.json`: 최근 실행 결과
- `cleanup.log`: 1MiB × 최대 4개 순환 로그
- `trash-seen.json`: 휴지통 첫 관측 시각
- `pending-slack.json`: 실패 알림 재시도 큐
- `run.lock`: 중복 실행 방지 flock

검증: `python3 -m unittest discover -s docs -p 'test_disk_cleanup.py' -v`.
테스트는 임시 폴더를 사용하고 실제 Slack/홈 데이터에 접근하지 않는다.
