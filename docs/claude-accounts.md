# Claude 계정과 사용자별 사용량

각 macOS 사용자는 자기 홈의 설정·인증·대화 기록을 사용한다.

| 사용자 | 실행 명령 | 설정 디렉터리 | 시작 패널 |
|---|---|---|---|
| Owen | `claude`, `claude2`, `claude3`, `claude4` | `~/.claude`, `~/.claude-b`, `~/.claude-c`, `~/.claude-d` | Claude 4개 + Codex 1개 |
| 하니 | `claude`, `claude2` | `~/.claude`, `~/.claude-b` | Claude 2개 + Codex 1개 |

`~/.claude-accounts.zsh`의 보조 계정 함수는 처음 호출할 때만 디렉터리를 만든다.
같은 OS 사용자 안에서 `settings.json`, `CLAUDE.md`, `plugins`, `skills`,
`projects`, `file-history`를 기본 계정과 심링크로 공유한다.
서로 다른 OS 사용자의 인증·대화 기록·메모리는 공유하지 않는다.

새 계정은 해당 사용자의 로그인 셸에서 초기화하고 로그인한다:

```zsh
# Owen
claude4 auth login

# 하니
claude2 auth login
```

`claude-usage`는 자기 홈의 계정 디렉터리를 발견한다. 로그인 전 계정도
`미로그인`으로 표시한다. Codex는 `~/.codex/auth.json`이 있으면 표시한다.
계정 추가·로그인 후에는 새 셸을 열면 된다 — 로그인 파일이 캐시보다 새로우면
60초 TTL을 기다리지 않고 다시 조회한다(2026-11-10). 손으로 볼 때는 `claude-usage`.

한 계정의 로그인은 두 곳에 따로 있을 수 있다. 화면 앞 터미널에서 한 로그인은
macOS 키체인에, SSH로 붙은 셸·tmux에서 한 로그인은 `<설정 디렉터리>/.credentials.json`에
저장된다(그 셸에서는 키체인이 잠겨 있다). 사용량 패널은 둘 다 읽고 살아 있는 쪽으로 조회한다.
CLI 자체는 자기 맥락의 저장소만 보므로, SSH에서만 쓰던 계정을 화면 앞 터미널에서
처음 띄우면 로그인을 한 번 더 요구할 수 있다(반대도 같다). 고장이 아니다.

사용량 API는 요청 제한이 빡빡하다(2분에 7~11번 → HTTP 429, 4~5분 차단).
패널에 `⚠ 조회 제한`이 뜨면 직전 값이 그대로 보이고, 표시된 시각 뒤에 저절로 풀린다.
`claude-usage -r`을 연달아 칠 필요는 없다(10초 안에는 같은 값을 쓴다).
목록을 명시하려면 각 사용자의 `~/.zshrc.local`에 설정한다:

```zsh
# 하니: 기존 Claude + 새 Claude + Codex
export CLAUDE_USAGE_ACCOUNTS="claude:$HOME/.claude,claude2:$HOME/.claude-b"
export CLAUDE_USAGE_CHATGPT="chatgpt:$HOME/.codex"
```

Hermes Logan(`studio`)·CS에는 각 프로필별 독립 OAuth 로그인을 등록한다:

```sh
hermes -p studio auth add anthropic --type oauth --label acct4
hermes -p cs auth add anthropic --type oauth --label acct4
```

각 인증 화면에서 새 계정을 확인한다. CLI 키체인, 다른 OS 사용자,
다른 Hermes 프로필의 refresh token을 복사하지 않는다. 회전되는 토큰을
두 저장소가 공유하면 한쪽의 갱신이 다른 쪽 로그인을 깨뜨린다.
등록 후 두 프로필의 `pool_usage.py --profile studio|cs`에서 새 후보를 확인한다.

플러그인 설정 비교는 사용자 홈 경로를 정규화한 뒤 수행한다.
Claude는 활성 플러그인·설치 레지스트리·마켓플레이스·스킬·훅의 실제 실행 경로,
Codex는 `config.toml`의 플러그인·마켓플레이스·스킬·MCP·훅을 함께 확인한다.
다른 사용자의 홈을 가리키는 절대 경로는 해당 사용자의 홈으로 바꾼다.
플러그인 설치 상태가 같아도 외부 서비스 로그인과 macOS 앱 권한은 사용자별이다.

하니의 기존 일반 설정·플러그인이 비어 있으면 관리자가 다음 도구로 설치한다:

```sh
python3 docs/setup_hani_agents.py  # 변경 계획만 출력
sudo python3 docs/setup_hani_agents.py --apply --login --email '<새 Claude 이메일>'
```

기존 파일은 `.bak.agent-setup-<시각>`으로 백업한다. Claude의 모델·추론·언어·
플러그인·상태 표시줄, Codex의 모델·추론·플러그인·스킬·MCP를 맞춘다.
하니의 기존 permissions·sandbox·hooks, 홈 AGENTS.md, 인증·대화·학습 메모리는 유지한다.
Owen의 Slack·Orca 알림 계정과 개인 권한 설정은 복제하지 않는다.
각 CLI 로그인은 하니 사용자로 따로 수행한다. Codex는 사용할 ChatGPT 계정을 직접 선택한다.
검증 결과는 `~hani/.local/state/agent-settings-sync/report.json`,
선택한 `--report <경로>`에도 기록한다. 토큰 값은 기록하지 않는다.
