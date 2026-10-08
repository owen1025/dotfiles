# macOS 주기적 디스크 청소

2026-09-29 용량 조사·수동 정리 후 같은 데이터가 다시 쌓이지 않도록 등록했다.
`com.owen.disk-cleanup` LaunchAgent가 매일 **04:30, 머신 현지 시각**에 실행한다.
사용자 로그인 세션에서 실행하며 잠자기 중 놓친 시각은 macOS launchd가 기상 후 처리한다.
기존 `com.owen.chrome-automation-gc`의 시간별 임시 브라우저 프로필 청소는 별도로 유지한다.

| 대상 | 보존 기간 | 보호 조건 |
|---|---:|---|
| npm·Chrome·Slack·Claude 캐시, CapCut 재생성 캐시(썸네일·파형·미리 렌더·미리보기 이미지 — 아래 10-08), 앱 업데이트 설치 파일 | 3일 | 최신 mtime/ctime, 열린 파일, 소유 앱 프로세스(Chromium 디스크 캐시는 제외 — 아래) |
| Chrome 앱 복제본 `X/com.google.Chrome.code_sign_clone/*` | 1일 | 실행 중 Chrome이 연 실행 파일, 프로세스 명령줄 |
| npx 패키지, 개발 검증/배포 복제 폴더(`lazyowen-web-deploy`·`-dev-deploy`), `/private/tmp/studio-sandbox/app/.next` | 7일 | 하위 전체 최신 수정·프로세스 명령줄·열린 파일 |
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
자동 정리 대상이 아니다.

### 2026-10-08 개정 — CapCut 은 재생성 캐시만

`CapCut 캐시` 규칙이 `~/Movies/CapCut/User Data/Cache` 전체를 3일 기준으로 지웠다. 그 아래
`effect/<id>/<md5>/`·`artistEffect`·`music` 은 캐시가 아니라 **프로젝트가 절대 경로로 가리키는 리소스**이고
`ressdk_db`·`cloudDraft` 는 리소스 목록·클라우드 SQLite 다. 파일 단위로 지우니 폴더 껍데기만 남아,
10-08 04:30 실행이 토킹탑 둥근 창 마스크 패키지(`effect/1068046537`)를 비웠고 그날 편집 자동화 export(git-trick)에서
캡컷이 그 마스크를 경고 없이 빼고 렌더했다(아래 띠 마스크만 보임). 캡컷은 지금 목록에 있는 이펙트만 다시 받고,
템플릿이 품은 옛 이펙트 번호는 다시 받지 않는다. 그날 이펙트 패키지 392개 중 149개가 빈 껍데기, 정리량은 하루
0.4~1.8GB(여유 178GB).

지금은 `CAPCUT_REBUILT_CACHES`(frameThumbnail·audioWave·segmentPrerenderCache·prerender·image·fontImage)만
지운다. 비워진 패키지 복구와 캡컷 열기 전 점검은 capcut-automation `capcut_cache`(같은 md5 사본·보관소에서 채움).

### 2026-10-02 개정 — 상시 실행 앱과 Chrome 복제본

첫 4회(09-29~10-02) 실행은 모두 0바이트를 지웠고 그사이 여유 공간은 38GB → 9.7GB로 줄었다.
이 Mac mini는 Chrome·Slack·Claude·CapCut이 늘 떠 있어서 "소유 앱 실행 중이면 그룹 전체 보존"
규칙에 걸린 캐시 8개 그룹이 한 번도 검사되지 않았다. Chrome·Slack·Claude의 `Cache`·`Code Cache`는
Chromium 디스크 캐시라 항목 파일이 사라져도 캐시 미스로 처리된다. 그래서 이 그룹만 `live=True`로
앱 실행 중에도 **열려 있지 않고 3일간 바뀌지 않은 파일**을 지운다. 인덱스처럼 계속 갱신되는 파일은
보존 기간에 걸려 남는다. 서비스워커 CacheStorage, CapCut 캐시·설치 파일, Claude VM은 여전히 앱이
실행 중이면 건너뛴다.

Chrome은 실행할 때마다 앱 번들을 `$TMPDIR/../X/com.google.Chrome.code_sign_clone/`에 APFS clone으로
복제하고 정상 종료 때 지운다. 자동화 Chrome(chrome-devtools-mcp·puppeteer)이 강제 종료되면 남아서
10-02에는 219개(표시 320GB)가 쌓였다. 실제 점유는 clone ID 기준 약 2.1GiB로, 디스크의 Chrome.app과
블록을 공유하지 않는 옛 버전 프레임워크였다. Chrome이 업데이트될 때마다 이 몫이 늘어난다. 실행 중인
Chrome은 자기 복제본의 실행 파일을 열어 두므로(lsof `txt`) 열린 파일 검사로 보호되고, 1일 보존 기간이
막 시작한 실행을 덮는다. 정리 대상은 `chrome-automation-gc`가 맡는 임시 프로필과 겹치지 않는다.
Logi 시스템 캐시는 사용자에게 쓰기 권한이 있을 때만 정리하며, 없으면 #ops에 보존 사유를
표시한다. 자동 sudo·암호 저장·앱 강제 종료는 하지 않는다.

### 이 머신에서 확인한 macOS 접근 권한 제한

2026-09-29 launchd 첫 실행에서 일반 캐시·런타임 검사는 정상 동작하고 Slack 발송도
성공했지만, `~/.Trash`와 Finder `TemporaryItems`는 `PermissionError`로 거부됐다.
터미널/에이전트 앱의 권한은 별도 launchd 프로세스에 자동으로 전달되지 않는다.
이 두 경로까지 자동 청소하려면 사용자가 **시스템 설정 → 개인정보 보호 및 보안 →
전체 디스크 접근 권한**에서 실행 인터프리터 `/opt/homebrew/bin/python3`를 허용해야 한다.
이 권한은 Python 프로세스의 다른 실행에도 적용되므로 사용자가 직접 결정·설정한다.
허용 전에는 두 경로를 건드리지 않고 나머지 청소는 계속한다. 이 거부는 매일 똑같이 반복되므로
오류·종료 코드 1로 세지 않고 Slack 보존 사유 "전체 디스크 접근 권한 필요"로만 보인다(2026-10-02부터).
다른 경로의 `PermissionError`는 여전히 오류로 보고한다.
Logi `/Library/.../cache`의 root 소유 권한은 별개이며 전체 디스크 접근 권한으로 해결되지 않는다.

## Slack

- 채널: `#ops` (`C0C4SVD21K4`, nioh 워크스페이스).
- 설정: `~/.config/disk-cleanup/config.json`.
- 발송: `~/.hermes/profiles/cs/scripts/slack_post.py`.
- 인증: 위 helper가 CS `.env`의 `SLACK_BOT_TOKEN`을 읽는다. 토큰을 dotfiles·plist·로그에 복사하지 않는다.
- 각 실행의 삭제 그룹, 관측 삭제량, 실제 여유 공간 전후, 보존 사유, 오류를 알린다.
- 여유 공간이 20GiB(`LOW_FREE`) 미만이면 경고 줄을 붙인다. 약 14.8GB 아래에서 macOS `deleted`가
  샌드박스 앱(KakaoTalk·macshot·Pasty 등)을 강제 종료하므로 그 전에 알린다.
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

선택 적용은 파일과 등록 스크립트를 두 단계로 실행한다. 새 설정 디렉터리는 파일이 아닌
디렉터리를 대상으로 지정해야 한다.

```bash
chezmoi apply --exclude=scripts ~/.local/bin/disk-cleanup ~/.config/disk-cleanup ~/Library/LaunchAgents/com.owen.disk-cleanup.plist
chezmoi apply ~/10-disk-cleanup.sh
```

상태는 `~/.local/state/disk-cleanup/`에 저장한다:

- `last-run.json`: 최근 실행 결과
- `cleanup.log`: 1MiB × 최대 4개 순환 로그
- `trash-seen.json`: 휴지통 첫 관측 시각
- `pending-slack.json`: 실패 알림 재시도 큐
- `run.lock`: 중복 실행 방지 flock

검증: `python3 -m unittest discover -s docs -p 'test_disk_cleanup.py' -v`.
테스트는 임시 폴더를 사용하고 실제 Slack/홈 데이터에 접근하지 않는다.
