# Multiroptcg — ONE PIECE CARD GAME 전용 Multirole (2026-07-08)

DyXel/Multirole을 OPTCG 전용 서버로 개조한 포크. 원전 클라이언트/코어
(`F:\edopcg_CODEX_INTEGRATED_20260701_FINAL_EDIT_BY_CLAUDE_FABLE`)와 세트로 동작한다.

## 코드 변경 (upstream 대비 3곳 + 설정)

1. **Endpoint/RoomHosting.cpp** — 모든 룸에 `DUEL_OPCG_MODE`(high 0x20 = bit 37)
   + `DUEL_NO_MAIN_PHASE_2`(low 0x200000) 강제. HostInfo 자체에 실리므로
   참가자/관전/재접속/리플레이 전부 상속(클라 netserver.cpp:379와 같은 원리).
2. **Room/Context.cpp CheckDeck** — OPCG 코드 대역(879999990~880099999,
   에일리어스 해소 후 판정 = 프린팅은 원본과 매수 합산)은 **같은 카드 4장**까지,
   OCG/TCG scope 검사 면제. 그 외 카드는 종전 3장/스코프 규칙 유지.
3. **YGOPro/CoreUtils.cpp StripMessageForTeam** — 뒷면 라이프(LOCATION_EXTRA +
   POS_FACEDOWN)로의 MOVE는 **주인 포함 전원에게 코드 마스킹**(라이프 재배열이
   누구에게도 정보를 흘리지 않음).
4. **etc/config.json** — 단일 레포 `optcg-data`(로컬 git)에서 스크립트(*.lua),
   DB(*.cdb), 코어(ocgcore.dll)를 전부 공급. hornet(코어 크래시 격리) + 룸당 로드.

무수정 통과 확인: MSG_OPCG_STATE(181) 등 커스텀 메시지는 분배 default가
EVERYONE이라 그대로 방송, 밴리스트 없는 룸(hash 0)은 네이티브 허용,
constant.lua→utility.lua→opcg_bootstrap 체인이 Dueling.cpp:111의 표준 프리로드로
자동 탑승, 뒷면 라이프 MOVE는 상대에겐 upstream 스트리핑이 원래 가림.

## 데이터 레포

`util/pack-optcg-data.ps1` 실행 → `E:\github\optcg-server-data`에 원전의
script(베이스+확장 lua 전부) + cards-opcg.cdb + ocgcore.dll(Win32)을 모아
git 커밋. **원전(스크립트/cdb/코어)이 바뀔 때마다 재실행** 후 서버 재시작
(또는 웹훅 포트로 pull 트리거).

## 빌드 (MSVC x86 — 이 머신 재현 레시피)

의존성: boost 1.86 헤더(`E:\github\boostroot` — include 정션 + meson의
"라이브러리 한 개는 있어야 함" 요구를 채우는 더미 `lib\libboost_system.lib`),
나머지(libgit2/openssl/sqlite3/fmt)는 `F:\vcpkg2` x86-windows-static의
pkg-config. meson/ninja/pkgconf는 pip 설치본.

```powershell
$scripts = "C:\Users\Administrator\AppData\Local\Python\pythoncore-3.14-64\Scripts"
$env:PATH = "$scripts;$env:PATH"
$env:BOOST_ROOT = "E:\github\boostroot"
$env:PKG_CONFIG_PATH = "F:\vcpkg2\installed\x86-windows-static\lib\pkgconfig"
# pip 런처 exe는 meson이 못 읽음 - .bin의 진짜 바이너리를 지정할 것
$env:PKG_CONFIG = "C:\Users\Administrator\AppData\Local\Python\pythoncore-3.14-64\Lib\site-packages\pkgconf\.bin\pkgconf.exe"
cmd /c '"C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars32.bat" && cd /d E:\github\Multiroptcg && meson setup build -Dbuildtype=release -Dfmt_ho=true && meson compile -C build'
```

산출물: `build\multirole.exe` + `build\hornet.exe` (Win32 — 원전 ocgcore.dll과
아키텍처 일치).

## 실행

```
E:\github\Multiroptcg\run\   ← multirole.exe + hornet.exe + config.json
cd run && .\multirole.exe    (config.json은 커런트 디렉토리에서 읽음)
```
기동 시 ./sync/optcg-data로 데이터 레포를 클론하고 7911(듀얼)/7922(로비 JSON)
리슨. 확인: `curl http://127.0.0.1:7922/` → `{"rooms":[]}`.

## 클라이언트 접속

원전 `bin\release\config\configs.json`의 servers에 **OPTCG-Local**
(127.0.0.1, duelport 7911, roomlistport 7922) 등록 완료 — 게임의 온라인
메뉴에서 서버 선택 → 방 만들기(밴리스트 없음/기본 설정)만 하면 된다. 외부
친구용은 servers의 address/roomaddress만 호스트 IP로 바꾼 사본을 배포.

## 남은 확인/과제

- 실클라 2인 접속 라이브 듀얼(버전 게이트 {41.0 / core 11.0} 매칭 포함).
- 쿼리(UPDATE_DATA) 경로의 자기 라이프 코드 노출은 upstream 지식모델 그대로
  (클라가 렌더하지 않아 실해는 없음) — 추후 하드닝 후보.
- GitHub(ClaudeFable5/Multiroptcg) 푸시는 유저 결정.
