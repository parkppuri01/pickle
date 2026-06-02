# PIC.kle — HANDOFF (단일 진실 문서)

> **마지막 업데이트**: 0.4.0 · **현재 상태**: 캡처·편집·보관·자동삭제·설정·공증DMG까지 동작하는 완성된 메뉴바 앱.
> **새 세션은 이 문서를 먼저 읽으면 컨텍스트가 잡힙니다.**
> 느낌/DNA 가이드는 형 앱에서 물려받은 [`../pickle-느낌브리프.md`](../pickle-느낌브리프.md) 참고.
>
> ⚠️ **개인정보 주의**: 서명에 쓰는 팀 ID·Developer ID 식별자는 **gitignore된 `Signing.xcconfig`** 에만 둡니다 (커밋 금지). 배포 자격증명은 `scripts/release.local.sh`(gitignore)에. 각각 `*.example` 템플릿을 복사해 채우세요.

---

## ★ 0.4.0 스냅샷

**한 줄**: PIC.kle 0.4.0 — 캡처·편집(펜/블러/워터마크)·보관·자동삭제·설정·아이콘 상태표시·공증DMG까지 동작하는 완성형 메뉴바 앱.

### 지금 동작하는 것 (검증 완료)
- 메뉴바 🥒 병 아이콘 + 그리드 히스토리 패널 (FocusablePanel, 바깥클릭 닫힘, 멀티모니터).
  - **자물쇠(고정) + ✕(닫기) 버튼**: 자물쇠 잠그면 포커스 잃어도 안 닫힘(✕로만 닫기). 마지막 잠금 상태 기억(UserDefaults).
  - **아이콘 상태표시**: 캡처 내역 있으면 피클병, 비면 빈병 (메뉴바 + 폴더 아이콘 둘 다).
- 단축키 3종 (Settings에서 변경 가능):
  - `⇧⌥S` 일반 캡처 → 바로 저장
  - `⇧⌥D` 기능 캡처 → 편집창
  - `⇧⌥A` 클립보드 복사 캡처 → **bottle에 저장 안 함**, 클립보드로만(PizzaClip 켜져 있으면 그쪽으로)
- 저장 위치: `~/Documents/pickle bottle` (Settings에서 변경 가능, 변경 시 경고).
- **편집기 3도구** (탭 순서 펜·블러·워터마크):
  - 펜(색7/굵기3) · 블러(가우시안+모자이크 / 브러시+영역, 강도 슬라이더) · 워터마크(텍스트 **AND** 로고 동시, 각각 독립 드래그·크기·투명도)
  - **⌘Z** 통합 되돌리기(펜/블러를 그린 순서대로). 저장=원본 해상도 합성 후 덮어쓰기.
- **자동삭제**: 기본 30일(끄기/7/14/30/60/90일). 지난 파일은 휴지통으로(복구 가능). 앱 실행 시 + 하루 1회.
- **Settings**(TabView 4탭): 단축키 / 워터마크(폰트·로고 프리셋·마지막 텍스트 기억) / 보관(자동삭제·저장위치+경고) / 정보.
- 히스토리 그리드: 1:1 썸네일, 더블클릭=편집, 단일클릭=선택, 🍕=클립보드 복사, 🗑=휴지통, 드래그아웃, Clear all(확인창).
- **배포**: 서명+공증+staple DMG (`bash scripts/release-test-dmg.sh` → `~/Downloads/PIC.kle-<버전>.dmg`).

### 핵심 환경/주의 (재현용)
- 번들 ID `com.Team-jAm.PICkle`. 서명/팀ID는 `Signing.xcconfig`(로컬), 공증 프로필은 `scripts/release.local.sh`(로컬).
- **항상 서명된 Release 빌드**로 테스트(ad-hoc 금지) → `/Applications`에 `ditto` 설치. 안 그러면 화면기록 권한 무한 재요청. (§5-B)
- 빌드: `xcodegen generate && xcodebuild -project PicKle.xcodeproj -scheme PicKle -configuration Release -derivedDataPath build -clonedSourcePackagesDirPath build/SourcePackages build`
- 새 .swift 파일 추가 시 `xcodegen generate` 다시 돌려야 인식됨. (에셋 추가는 불필요)
- App Sandbox OFF / Hardened Runtime ON. 의존성: KeyboardShortcuts(정적). GRDB/Sparkle 미사용(folder-as-truth).

### 미완료 / 다음 (0.5.0~)
- [ ] 🥒 이스터에그 burst (`pickle`/`피클` 트리거) — 형 PizzaBurst 패턴 이식.
- [ ] Sparkle 자동 업데이트 + appcast 호스팅 — GitHub repo(`parkppuri01/pickle`) 생겼으니 Releases/Pages로 진행 가능.
- [ ] 메뉴바 아이콘 단계별(개수) 연출 — 추가 PNG 시안 필요.
- 미해결 리스크: folder-as-truth라 bottle 폴더를 공용폴더로 바꾸면 남의 이미지도 그리드/ClearAll 대상 → Settings에 경고 표시는 해둠.

---

## 0. 한 줄 정체성

**PIC.kle** = macOS 메뉴바 **스크린샷 캡처·편집·보관** 유틸리티.
형 앱 **pizzaClip(클립보드 히스토리)** 의 형제 — 구조·느낌은 같게, 테마는 🥒 **초록 피클**.

- 형: 텍스트(클립보드)를 모은다 → 동생: **스크린샷(이미지)를 모은다**.

---

## 1. 기능 전체

1. **자동 폴더** — `~/Documents/pickle bottle` 자동 생성. 스크린샷은 데스크탑이 아니라 이 폴더에 저장.
2. **자동삭제** — 지정 기간 지난 파일 자동 휴지통(기본 30일, Settings 조절·끄기).
3. **단축키 3종** — `⇧⌥S` 일반 / `⇧⌥D` 기능(편집) / `⇧⌥A` 클립보드 복사(저장 안 함).
4. **편집창** — 펜 · 블러/모자이크(브러시+영역) · 워터마크(텍스트+로고 동시, 각각 드래그). ⌘Z 되돌리기.
5. **히스토리 창** — 🥒 병 아이콘 클릭 → 그리드 썸네일. 자물쇠/닫기, Clear all, Settings, 드래그앤드롭.
6. **이스터에그** — (예정) 트리거 시 🥒 burst.

---

## 2. 확정된 설계 결정

| 결정 | 선택 | 이유 |
|---|---|---|
| 캡처 | macOS 기본 `screencapture` 셸아웃 | 구현 간단·안정, 영역 UI 자작 불필요, 권한 단순 |
| 저장 | **folder-as-truth** (DB 없음) | 스크린샷이 곧 실제 파일 → 드래그아웃/Finder 통합 거저. 메타데이터 필요해지면 그때 DB |
| 워터마크 | 텍스트 + 로고 **동시**, 각각 독립 | 이름/날짜 글자 + 브랜드 로고 둘 다, 위치·크기 따로 |
| 블러 | 가우시안+모자이크 / 브러시+영역 | 부분(브러시)·큰영역(드래그) 둘 다 |
| 자동삭제 | 기본 30일, 휴지통行 | 보관함 무한증가 방지 + 복구 가능 |
| 클립보드 캡처(A) | bottle 저장 안 함 | 빠른 1회성 복사·PizzaClip 연동 |
| 서명 | Manual + Developer ID, 값은 `Signing.xcconfig`(로컬) | 안정 서명으로 TCC 권한 유지(§5-B) + 개인정보 비커밋 |
| App Sandbox | OFF (Hardened Runtime ON) | `screencapture` 셸아웃 + 임의 경로 쓰기 때문 |

---

## 3. 아키텍처 골격 (형에서 물려받음)

**SwiftUI + AppKit 혼합, 메뉴바 전용(`LSUIElement=YES`)**.

- **Composition root**: `App/AppDelegate` 가 모든 wiring 허브 (상태바·옵저버·단축키·자동삭제·아이콘).
- **느슨한 연결**: `Notification.Name` 확장(`.pickle*`)으로 컴포넌트 통신.
- **저장**: folder-as-truth. `ScreenshotStore` 가 폴더를 직접 읽음.

```
PicKle/
├── App/            # @main, AppDelegate(허브), AppPaths, Notifications
├── Capture/        # screencapture 호출(파일/클립보드), 권한 헬퍼
├── DesignSystem/   # Colors(피클그린), Theme(토큰)
├── Editor/         # EditorModel/View/WindowController (펜·블러·워터마크)
├── History/        # 패널·그리드·뷰모델·썸네일 로더
├── MenuBar/        # PickleIcon (빈병/피클병)
├── Settings/       # SettingsView (4탭)
├── Shortcuts/      # KeyboardShortcuts 등록 (S/D/A)
├── Storage/        # ScreenshotStore, RetentionService, WatermarkPresets,
│                   #   FolderIcon, ClipboardService
└── Resources/      # Info.plist, entitlements, Assets.xcassets
```

---

## 4. 디자인 시스템

피클 그린 `accent`: `#3B6B2F`(light) / `#6FAE4E`(dark). 패턴: `Color(light:dark:)` 적응형 쌍.
모양 토큰: `panelRadius=14`, `rowRadius=8`. 편집 캔버스는 최대 1000×640로 표시 스케일.

### 아이콘 자산 (`guide/`)
- 앱 아이콘: `피클 앱아이콘.png`(1024) → `AppIcon.appiconset`.
- 메뉴바: `상단메뉴바 아이콘.png`(피클병) / `메뉴바 아이콘 빈병.png`(빈병) → 18·36px 에셋. `isTemplate=false`.
- 폴더 아이콘: `빈병.png` / `피클병.png` (파란 폴더+병 엠보싱) → 1024 정사각 에셋, `NSWorkspace.setIcon`으로 bottle 폴더에 적용.

---

## 5. ⚠️ 코드 서명 & 권한(TCC)

**문제**: ad-hoc(무서명) 빌드는 빌드마다 코드 "지문"이 바뀜 → TCC가 매번 다른 앱으로 보고 Screen Recording 권한을 안 기억함(허용해도 무한 재요청).

**해결**: Manual + Developer ID 서명으로 지문 고정. 서명 값(팀ID·식별자)은 **`Signing.xcconfig`(gitignore)** 에 두고 `project.yml`의 `configFiles`로 참조 → 개인정보 비커밋 + 안정 서명.

**개발 워크플로우**:
- 항상 서명된 Release 빌드(`-configuration Release`, `CODE_SIGNING_ALLOWED=NO` 쓰지 말 것).
- `/Applications`에 `ditto` 설치해 실행.
- 권한 꼬이면: `tccutil reset ScreenCapture com.Team-jAm.PICkle`.
- Screen Recording 권한 허용 후 앱 재시작 필요.
- 번들 ID 바꾸면 macOS가 새 앱으로 봐서 권한 1회 재부여 필요.

### 테스트 배포 DMG
- `scripts/release-test-dmg.sh` — Release 빌드를 ① 타임스탬프+하드닝 재서명 → ② 앱 공증(`notarytool`) → staple → ③ DMG 생성 → 서명 → ④ DMG 공증 → staple. 결과 `~/Downloads/PIC.kle-<버전>.dmg`.
- 서명 식별자·공증 키체인 프로필은 **`scripts/release.local.sh`(gitignore)** 에서 주입(`PICKLE_SIGN_IDENTITY` / `PICKLE_NOTARY_PROFILE`).
- 핵심 주의: xcodebuild 기본 서명은 `--timestamp=none`이라 공증 거부 → 스크립트가 `--timestamp`로 재서명함.

---

## 6. 버전 로드맵

- **0.1.0** ✅ 뼈대 + 빈 앱(메뉴바·폴더·패널 골격).
- **0.2.0** ✅ 캡처 + 저장(folder-as-truth) + 그리드.
- **0.3.0** ✅ 편집기(펜·워터마크·블러) + 공증 DMG.
- **0.4.0** ✅ 자동삭제 · Settings 4탭 · ⇧⌥A 클립보드 캡처 · 편집기 개선(탭 순서·⌘Z·텍스트+로고 동시) · 히스토리 자물쇠/닫기 · 빈병↔피클병 아이콘(메뉴바+폴더).
- **0.5.0~** ⏳ 이스터에그 burst · Sparkle 자동 업데이트(appcast) · 메뉴바 단계별 연출.

---

## 7. 협업 스타일
사용자는 바이브코더 → **쉬운 한국어**, 전문용어는 한 줄 풀이, 코드 바꿀 때 **"무엇을/왜"** 요약.
