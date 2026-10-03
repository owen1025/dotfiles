# 맥 간 Desktop/inbox 동기화

`syncthing-inbox`는 macOS의 `~/Desktop/inbox`를 Tailscale로 양방향 동기화한다.
파일 추가·수정·삭제가 모두 전파된다. 각 맥에 파일 사본이 생기며, 오프라인 중의 변경은
두 맥이 다시 연결되면 반영된다. Jump Desktop 연결 여부와는 관계없다.

2026-10-03 studio ↔ studio-th 설정: 기존 Syncthing 인증서가 맥 이관 과정에서 복사돼
장치 ID가 같았다. 기존 challenge/hermes 인스턴스와 분리한 전용 인스턴스를 사용한다.

## 설정

1. 양쪽에 Homebrew Syncthing과 Tailscale을 설치하고 Tailscale을 연결한다.
2. 양쪽에서 `syncthing-inbox init`을 실행해 **서로 다른** 장치 ID를 받는다.
3. 양쪽에서 `syncthing-inbox pair <상대 장치 ID> <상대 Tailscale IPv4>`를 실행한다.
4. `syncthing-inbox status`로 연결·남은 파일·오류를 확인한다.

서비스는 로그인 시 자동 시작한다. 관리 화면은 각 맥의 http://127.0.0.1:8385 이다.
포트 22001/TCP를 사용하고, 공개 장치 검색·릴레이·자동 포트 포워딩은 끈다.
상대 장치 ID와 명시한 Tailscale 주소로만 연결하며 자동 폴더 수락은 끈다.

- 설정·개인키·DB·회전 로그: `~/Library/Application Support/Syncthing-Inbox/`
- LaunchAgent: `~/Library/LaunchAgents/com.owen.syncthing-inbox.plist`
- 일시 중지: 관리 화면에서 Desktop inbox를 일시 중지한다.
- 서비스 종료: `launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.owen.syncthing-inbox.plist`
- 재시작: `syncthing-inbox init`

장치 키·API 키·DB는 머신별 런타임 상태이므로 git/chezmoi로 복사하지 않는다.
양쪽에서 동시에 같은 파일을 수정하면 Syncthing이 충돌 사본을 만들 수 있다.
별도 버전 보관은 설정하지 않으므로 동기화를 백업으로 사용하지 않는다.

공식 문서: https://docs.syncthing.net/users/syncing.html
