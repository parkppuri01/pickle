# 피클(pickle) — 느낌 브리프 / DNA 문서

> **이 문서의 목적**: 형(pizzaClip)의 "느낌"만 동생(pickle)에게 물려주기 위한 레시피.
> 새 세션 첫 메시지에서 이 파일을 읽히고 시작하세요: *"이 문서가 자매품 형 앱의 느낌이야. 피클 앱은 이 느낌을 유지하되 색·이름·마스코트는 피클로 바꿔서 만들 거야."*
>
> ⚠️ **코드를 복사하지 마세요.** 이건 쌍둥이가 아니라 형제입니다. 뼈대(구조)는 같게, 표면(색·이름·기능)은 다르게.
> 작성: 2026-06-02 · 출처: pizzaClip `docs/HANDOFF.md` + 실제 소스

---

## 0. 한 줄 정체성

- **형 (pizzaClip)**: macOS 메뉴바 클립보드 히스토리 앱. 빨강/노랑 피자 테마, 🍕 장난기.
- **동생 (pickle)**: macOS 메뉴바 앱(기능은 새 세션에서 정함). **초록 피클 테마, 🥒 장난기.** 형과 한눈에 "같은 집안"으로 보이되 다른 앱.

> 피클이 **무슨 일을 하는 앱인지(기능)**는 이 문서 범위 밖입니다 — 새 세션에서 정하세요. 이 문서는 **"어떤 느낌/태도로 만드는가"**만 정의합니다.

---

## 1. 브랜드 성격 (제일 중요 — 이게 "느낌"의 핵심) 🥒

형의 매력은 "도구인데 귀엽고 장난기 있다"는 점. 동생도 이 태도를 물려받습니다.

1. **음식 이름 + 음식 마스코트**: 피자 → 피클. 앱 곳곳에 마스코트가 등장.
2. **단계별 마스코트 아이콘**: 형은 메뉴바 아이콘이 히스토리 개수에 따라 피자 슬라이스 1~7개 → 피자박스로 변함(PNG 10단계). → 동생도 **상태를 마스코트 단계 PNG로 표현** (예: 피클 1조각 → 한 병 가득). 사용자가 PNG를 제공하면 `Assets.xcassets/...Icon0~9.imageset`로 번들.
3. **이스터에그 burst**: 형은 클립보드 텍스트가 정확히 `pizza` 또는 `피자`일 때 🍕 48개가 팝콘처럼 튀어오르는 2.4초 애니메이션. → 동생은 `pickle`/`피클` 트리거 + 🥒 burst. (SwiftUI `ForEach`+`.position`+`.rotationEffect`, `TimelineView(.animation)`, `.task(id:)` 트리거 — 구현 패턴 그대로 재사용 가능)
4. **말투**: UI 문구는 담백하고 친절. 과한 전문용어 없음. 푸터 액션 단어에 포인트 색.
5. **절제**: 장난기는 "가끔, 정확히 트리거될 때만". 형은 부분매치 이스터에그가 너무 자주 떠서 exact match로 줄인 교훈이 있음 → 동생도 **트리거는 정확 일치로** 시작.

---

## 2. 디자인 시스템 — 구조는 복사, 색은 교체 🎨

### 2-1. 색 "역할" 구조는 그대로 (이게 자매품 통일감의 핵심 장치)

형의 색 시스템은 단순히 "무슨 색"이 아니라 **3가지 역할 + 라이트/다크 적응 쌍**으로 짜여 있음. 이 **구조를 그대로 쓰고 색 값(hex)만 피클색으로** 바꾸면 "형제 같은데 다른" 느낌이 완성됨.

| 역할 | 무슨 용도 | 형(피자) 값 (light / dark) | 동생(피클) 제안 — *새 세션에서 확정* |
|---|---|---|---|
| `accent` | 선택·앱 틴트·푸터 액션 단어 | `#A2371F` / `#D55C38` (벽돌빨강→테라코타) | 피클그린 계열 (예: `#3B6B2F` / `#6FAE4E`) |
| `amber` | 슬롯 번호 배지·핀 마커 (텍스트/스트로크) | `#B57500` / `#FFB703` (골드) | 디종 머스타드 옐로 또는 딜 그린 (대비용 보조색) |
| `amberFill` | 채워진 칩 배경 (예: "0" 배지) | `#F5A800` / `#FFB703` | 위 보조색의 밝은 버전 |
| `inkOnAmber` | 칩 위에 얹는 글자색 | `#102138` (딥 네이비) | 어두운 잉크색 유지 (예: `#10261A` 딥 그린-블랙) |

> **핵심 패턴**: 색은 `Color(light: 0xRRGGBB, dark: 0xRRGGBB)` 형태의 **적응형 쌍**으로 정의. 라이트모드는 진하게(밝은 유리 위 가독성), 다크모드는 선명하게. 중립색(separator 등)은 `NSColor` 시스템값 그대로. → **이 `Colors.swift` 패턴 파일을 통째로 가져가서 hex 값만 교체**하면 됨.

### 2-2. 모양 토큰은 거의 그대로 (형제 통일감)

```
panelRadius = 14   (패널 모서리)
rowRadius   = 8    (행 모서리)
panelWidth  = 440
panelHeight = 480
accent 보조: 코랄/테라코타 톤의 따뜻함  →  피클은 차분한 그린 톤
```
> 모서리 둥글기·여백 감각은 유지하면 한 집안 느낌. 크기는 동생 기능에 맞게 조정 가능.

---

## 3. 아키텍처 · 컨벤션 골격 🏗️

형의 구조 = **SwiftUI + AppKit 혼합, 메뉴바 전용 앱(LSUIElement)**. 동생도 같은 골격으로 시작.

- **메뉴바 앱**: `Info.plist`에 `LSUIElement=YES` (독 아이콘 없음, 상태바에만 존재).
- **Composition root 패턴**: `App/` 폴더에 `AppDelegate`가 모든 wiring + 상태바 + 옵저버 담당. `@main` struct는 얇게.
- **기능별 폴더 분리** (형의 방식):
  ```
  App/          # @main, AppDelegate(wiring 허브), 경로
  DesignSystem/ # Colors.swift(역할색), Theme.swift(토큰)  ← 거의 그대로 이식
  MenuBar/      # 상태바 아이콘(개수→PNG 매핑)
  Settings/     # SwiftUI Settings 씬 (TabView)
  Permissions/  # 권한 헬퍼 (필요 시)
  Resources/Assets.xcassets/  # 마스코트 단계 PNG
  ... (기능 폴더는 동생 기능에 맞게)
  ```
- **이미지/저장이 필요하면**: 형은 GRDB(SQLite) + 파일 BlobStore 사용. 동생이 저장이 필요하면 같은 조합 추천.
- **단축키**: `KeyboardShortcuts` 패키지로 사용자 변경 가능한 글로벌 단축키.
- **상태 알림**: `Notification.Name` 확장으로 컴포넌트 간 느슨한 연결 (형의 `.pizzaClip*` → 동생 `.pickle*`).

---

## 4. 빌드 · 배포 파이프라인 🔧 (거의 그대로 재사용)

형의 배포 골격은 검증됨 — 동생도 이름만 바꿔 재사용.

- **프로젝트 생성**: `xcodegen` + `project.yml`이 단일 소스 오브 트루스 (`.xcodeproj`는 gitignore). 의존성: GRDB / KeyboardShortcuts / Sparkle.
- **타깃 설정 골격** (`project.yml`): macOS 13+, Swift 5.9, **Manual 서명 + Developer ID + Hardened Runtime + `--timestamp` + entitlements**.
- **자동 업데이트**: Sparkle 2 + `appcast.xml` 호스팅. (형은 `pizza-clip.com/appcast.xml`)
- **release.sh 한방 스크립트**: 테스트 → Release 유니버설 빌드 → Sparkle 헬퍼 재서명 → .app 공증·staple → DMG 서명·공증·staple → `/Applications` 설치 → ZIP EdDSA 서명 + appcast `<item>` 생성. **이 스크립트를 복사해 이름/경로/도메인만 바꾸면 됨.**
- **서명 ID**: Developer ID Application (팀 ID·식별자는 gitignore된 `Signing.xcconfig`에 로컬 보관) — 형/동생 같은 개발자 계정.
- **번들 ID**: `com.jekeun.pickle` (형은 `com.jekeun.pizzaClip`).

---

## 5. 문서화 · 협업 컨벤션 📝 (이것도 물려받으면 좋음)

형이 잘 굴러간 이유 중 하나는 문서 습관. 동생도 1일차부터 적용 추천.

- **`docs/HANDOFF.md`**: 새 세션이 한 번 읽으면 컨텍스트가 잡히는 단일 진실 문서. 맨 위에 "마지막 업데이트 + 현재 상태 한 줄". "다음 버전 범위(확정)" 섹션으로 다음 할 일을 명확히.
- **설계 결정 테이블**: `| 결정 사항 | 이유 |` 표로 "왜 이렇게 했는지"를 남김 → 나중에 번복/혼동 방지.
- **버전마다 변경점 기록**: 0.1.x 단위로 뭐가 바뀌었는지 누적.
- **사용자 협업 스타일**: 사용자는 바이브코더 → 쉬운 한국어, 전문용어는 한 줄 풀이, "무엇을/왜" 요약. (형 작업 내내 지킨 규칙)

---

## 6. 새 세션 시작 체크리스트 ✅

새 피클 세션에서 이 순서로 시작하면 됨:

1. 이 문서를 읽힌다 → "형의 느낌을 이걸로 잡고 가자."
2. **피클이 무슨 앱인지(기능) 정한다.** ← 이게 비어있음. 먼저 결정.
3. `Colors.swift` / `Theme.swift` / `release.sh` / `project.yml` 골격을 **형에서 복사 → 이름·색·도메인만 피클로 교체.** (형 앱 pizzaClip 레포 참고)
4. 마스코트 PNG(상태 단계 + 이스터에그 파티클)는 사용자가 따로 제공.
5. `docs/HANDOFF.md`를 1일차부터 시작.

---

### 부록: 형에서 그대로 떠올 가치 있는 "패턴 파일" 목록
> 복사하되 **값/이름만 교체** (로직은 검증됨):
- `pizzaClip/DesignSystem/Colors.swift` — 역할색 + light/dark 적응 패턴
- `pizzaClip/DesignSystem/Theme.swift` — 모양 토큰
- `scripts/release.sh` — 빌드·서명·공증·배포 한방
- `project.yml` — xcodegen 프로젝트 정의 골격
- `pizzaClip/Popup/PizzaBurst.swift` — 이스터에그 burst 애니메이션 패턴
- `pizzaClip/MenuBar/PizzaIcon.swift` — 개수→PNG단계 매핑 패턴
