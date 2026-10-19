# Mac mini 내부망 원격 접속

2026-10-19 확인한 `owen-lolui-Macmini`의 유선 IP는 `192.168.219.103`,
Wi-Fi IP는 `192.168.219.104`다. DHCP 주소이므로 바뀔 수 있다.

## SSH / mosh

원격 로그인과 mosh는 이미 설치·활성화되어 있다. 차단은 두 겹이다.

1. `/etc/ssh/sshd_config.d/040-lazyowen-tailscale-only.conf`의 `AllowUsers`가
   Tailscale 출처만 허용한다.
2. PF 앵커 `com.apple/990.lazyowen`이 TCP/UDP 22·88·3283·5900을
   Tailscale·루프백 이외의 출처에서 차단한다. macOS 앱 방화벽이 꺼져 있어도
   이 규칙은 작동한다. 이 Mac 내부에서 자기 IP로 검사하면 루프백 예외로
   성공하므로, 반드시 다른 기기에서 검사해야 한다.

`mac-lan-ssh`는 SSH에 `owen@192.168.219.0/24`를 추가하고,
`/Library/Application Support/lazyowen/pf-tailscale-only.conf`와 실행 중 PF
앵커에 en0/en1의 내부망 출처 TCP 22·5900, UDP 5900~5902만 허용한다.
mosh UDP 60000~61000은 원래 PF 차단 대상이 아니다. 기존 SSH 키 인증·
Tailscale 허용·외부 차단은 유지하며, 전체 PF나 라우터 설정은 바꾸지 않는다.

```sh
mac-lan-ssh                            # 변경 미리보기
sudo ~/.local/bin/mac-lan-ssh --apply   # 이 Mac에서 관리자 인증 후 적용
```

sshd 설정 검증에 실패하면 SSH 파일을, PF 적용에 실패하면 PF 파일과
직전 실행 규칙을 복원한다. SSH 백업은
`/etc/ssh/040-lazyowen-tailscale-only.conf.backup-*`에 보관하며 SSH Include
대상 밖이다. PF 백업은 기존 PF 파일과 같은 디렉터리에 둔다.
SSH가 이미 적용됐더라도 PF 적용을 생략하지 않는다.

2026-10-19 재현: 다른 Mac `192.168.219.101`에서 `.103`과 `.104`의
22·5900이 모두 시간 초과, Tailscale `100.74.65.14`의 같은 포트는 연결 성공.
이 차이를 확인해야 단순 SSH 인증 문제와 PF 차단을 구별할 수 있다.

접속하는 기기의 터미널에서 실행한다. 해당 기기의 SSH 키가 이 Mac의
`~/.ssh/authorized_keys`에 등록되어 있어야 한다. 현재 등록된 것은 본인
MacBook과 이전 Mac mini의 키다.

```sh
mosh --server=/opt/homebrew/bin/mosh-server owen@192.168.219.103
# Wi-Fi 주소로 접속할 때는 192.168.219.104 사용
```

## GUI 조작

이 Mac은 ‘시스템 설정 → 일반 → 공유 → 원격 관리’가 켜져 있고 화면 관찰·제어가
허용되어 있다. 그래서 별도의 ‘화면 공유’ 스위치는 회색으로 보인다.
원격 관리에서도 화면 공유 앱으로 접속할 수 있다.

다른 Mac의 ‘화면 공유’ 앱에서 `192.168.219.103`을 추가하거나 Finder의
‘서버에 연결’에서 `vnc://192.168.219.103`을 연다. 등록 사용자 `owen`과
이 Mac의 로그인 암호를 사용한다. GUI의 로그인 암호와 SSH 공개키 인증은 별개다.

양쪽 모두 Apple silicon이고 macOS Sonoma 14 이상이면 ‘고성능’을 권장한다.
저지연·30/60fps·오디오·가상 디스플레이를 지원한다. 같은 사용자로 접속하면
대상 Mac의 물리 화면은 가려진다. 유선 연결이 권장된다.

- [Apple: 화면 공유 모드 및 요구사항](https://support.apple.com/guide/mac-help/mchl1883115d/mac)
- [Jump Desktop: Windows·iPad 등에서 접속](https://docs.jumpdesktop.com/start/quick-start/)

Jump Desktop Connect도 이미 설치되어 있다. 다른 OS나 iPad에서 자주 조작한다면
Jump Desktop의 Fluid 연결을 대안으로 고려할 수 있다. 계정 연결·접근 권한 상태는
앱에서 확인해야 한다.
