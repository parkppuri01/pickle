# PICkle — HANDOFF (단일 진실 문서)

> **마지막 업데이트**: 2026-06-08 세션 · 0.4.0 기반 · 0.5.0 작업 진행중 · **현재 상태**: 위 기능에 더해 **편집기 UX 대수술** 반영 — 떠있는 도구 팝오버(자동 숨김)·**캔버스에서 워터마크 직접 입력(NSTextView)**·문단정렬(좌/중/우)·자간/줄간격·변(edge) 기준 스냅 가이드, 그리고 캡처 중 **스페이스바 영역 이동**·편집기 **배율(%) 표시**까지. 실기검증 완료.
> **새 세션은 이 문서를 먼저 읽으면 컨텍스트가 잡힙니다.**
> **▶ 다음 세션 할 일: 사용자가 새로 요청할 수정부터. 직전 2026-06-08 세션(편집기 UX 대수술 + 캡처 스페이스 이동)은 모두 완료·실기검증·커밋됨 — 아래 [✅ 2026-06-08 세션 완료] 참고. 알려진 후속(보류): ①편집 입력칸이 캔버스 `scaleEffect` 안에 있어 한글 IME 후보창 위치가 살짝 어긋날 수 있음 → 안정화 확인됐으면 "입력칸만 scaleEffect 밖으로 분리"로 다듬기 ②Sparkle 호스팅(1.0) ③단축키 설명 문구 갱신(소).**
> 느낌/DNA 가이드는 형 앱에서 물려받은 [`../pickle-느낌브리프.md`](../pickle-느낌브리프.md) 참고.
>
> ⚠️ **개인정보 주의**: 서명에 쓰는 팀 ID·Developer ID 식별자는 **gitignore된 `Signing.xcconfig`** 에만 둡니다 (커밋 금지). 배포 자격증명은 `scripts/release.local.sh`(gitignore)에. 각각 `*.example` 템플릿을 복사해 채우세요.
>
> 📛 **이름 표기 규칙(중요)**: 사용자에게 보이는 **브랜드 = `PICkle`**(점·소문자 없이 통일). 단, **번들 ID는 `com.Team-jAm.PICkle`**(건드리면 TCC 권한 깨짐), **Xcode 프로젝트/스킴/소스폴더 이름은 `PicKle`(대문자 K)** 로 그대로 둡니다(내부 식별자라 화면에 안 보임).

---

## ★ 현재 스냅샷 (0.4.0 + 0.5.0 진행분)

**한 줄**: PICkle — 캡처·편집(펜/블러/워터마크)·보관·자동삭제·설정·아이콘 상태표시·공증DMG + **다국어(한/영)** 까지 동작하는 완성형 메뉴바 앱.

### 지금 동작하는 것 (검증 완료)
- 메뉴바 🥒 병 아이콘 + 그리드 히스토리 패널 (FocusablePanel, 바깥클릭 닫힘, 멀티모니터).
  - **자물쇠(고정) + ✕(닫기) 버튼**: 자물쇠 잠그면 포커스 잃어도 안 닫힘(✕로만 닫기). 마지막 잠금 상태 기억(UserDefaults).
  - **아이콘 상태표시**: 캡처 내역 있으면 피클병, 비면 빈병 (메뉴바 + 폴더 아이콘 둘 다).
- 단축키 3종 (Settings에서 변경 가능) → 누르면 **자체 영역선택 오버레이(⇧⌘5식)** + 모드바가 뜨고, 모드 프리셀렉트됨:
  - `⇧⌥S` 저장(바로 bottle) / `⇧⌥D` 편집(편집창) / `⇧⌥A` 클립보드(**bottle에 저장 안 함**, PizzaClip 켜져 있으면 그쪽으로)
  - 드래그로 영역 선택 → 캡처(ScreenCaptureKit, 멀티모니터 OK). **드래그 중 스페이스바 누른 채 이동 = 선택영역 통째 이동**(⇧⌘5식, 떼면 다시 크기조절). ←/→ 모드변경, Esc/✕ 취소.
- 저장 위치: `~/Documents/PICkle bottle` (Settings에서 변경 가능, 변경 시 경고).
- **편집기 3도구** (왼쪽 아이콘 레일 + **선택 시 옆에 떠있는 옵션 팝오버**, 마우스 떠나면 ~2초 후 자동 페이드 / 선택 툴 재클릭=토글):
  - 펜(색7/굵기3) · 블러(가우시안+모자이크 / 브러시+영역, 강도 슬라이더) · 워터마크(텍스트 **AND** 로고 동시, 각각 독립 드래그·크기·투명도)
  - **워터마크 텍스트는 캔버스에서 직접 입력**(NSTextView): Enter=줄바꿈 / 바깥클릭·Esc=확정 / 더블클릭=재편집. **문단정렬(좌/중/우)·자간·줄간격** 조절. 드래그 시 **변(edge) 기준 스냅 가이드**(좌=왼쪽변·우=오른쪽변·상/하=위/아래변·가운데=중심).
  - **배율(%)**: 우측 상단 px 옆에 현재 표시 배율 실시간 표시.
  - **⌘Z** 통합 되돌리기(펜/블러를 그린 순서대로). 저장=원본 해상도 합성 후 덮어쓰기.
- **자동삭제**: 기본 30일(끄기/7/14/30/60/90일). 지난 파일은 휴지통으로(복구 가능). 앱 실행 시 + 하루 1회.
- **다국어(한국어/영어 런타임 전환)**: Settings → 정보 탭에서 `시스템 / 한국어 / English` 선택. 앱 재시작 없이 전환(설정창은 즉시, 다른 창은 다음 열 때). 기본=시스템 언어.
- **Settings**(TabView 4탭): 단축키 / 워터마크(폰트·로고 프리셋·마지막 텍스트 기억) / 보관(자동삭제·저장위치+경고) / 정보(+언어 선택).
- 히스토리 그리드: 1:1 썸네일, 더블클릭=편집, 단일클릭=선택, 🍕=클립보드 복사, 🗑=휴지통, 드래그아웃, Clear all(확인창).
- **배포**: 서명+공증+staple DMG (`bash scripts/release-test-dmg.sh` → `~/Downloads/PICkle-<버전>.dmg`).

### 핵심 환경/주의 (재현용)
- 번들 ID `com.Team-jAm.PICkle`. 서명/팀ID는 `Signing.xcconfig`(로컬), 공증 프로필은 `scripts/release.local.sh`(로컬).
- **항상 서명된 Release 빌드**로 테스트(ad-hoc 금지) → `/Applications`에 `ditto` 설치. 안 그러면 화면기록 권한 무한 재요청. (§5)
- 빌드: `xcodegen generate && xcodebuild -project PicKle.xcodeproj -scheme PicKle -configuration Release -derivedDataPath build -clonedSourcePackagesDirPath build/SourcePackages build` (결과물은 `PICkle.app`).
- 새 .swift 파일 추가 시 `xcodegen generate` 다시 돌려야 인식됨. 다국어 `.lproj`(en/ko)도 xcodegen이 변형 그룹으로 자동 인식.
- App Sandbox OFF / Hardened Runtime ON. 의존성: KeyboardShortcuts(정적). GRDB/Sparkle 미사용(folder-as-truth).

### 미완료 / 다음 (0.5.0~)
- [ ] **Sparkle 배포 마무리(호스팅)** — *1.0 출시 때 진행 예정 (보류)*. 앱 코드/서명/스크립트는 완료. 남은 건 *사용자 수동 단계*: ①`scripts/release-test-dmg.sh`로 DMG → ②`scripts/sparkle-appcast.sh`로 EdDSA 서명+appcast 생성 → ③DMG를 GitHub Release에 올리고 그 URL을 appcast `<enclosure>`에 기입 → ④appcast.xml을 형 web의 `web/public/pickle/appcast.xml`에 두고 배포(Vercel) → 브라우저로 `https://pizza-clip.com/pickle/appcast.xml` 열려 확인.
- [ ] **편집 입력칸 `scaleEffect` 분리 (후속, 보류)** — 워터마크 입력칸(NSTextView)이 캔버스 축소 변환 안에 있어 **한글 IME 후보창 위치가 구조적으로 어긋남**(architect 자문). *편집칸만 scaleEffect 밖으로 빼서 좌표변환 배치* 권고(`textWM.center*s`로 화면좌표, 폰트는 이미 스케일된 크기). (2026-06-08 세션 참고)
- [ ] **편집기 디자인 세부 조정** — 툴바 팝오버(시안 B)·캔버스 직접입력·정렬/자간/줄간격 완료. 예시(`guide/편집팝업예시.png`)의 추가 도구(화살표·도형·자르기·스티커 등)는 추후.
- [ ] **단축키 설명 문구 갱신(소)** — Settings 단축키 탭/`history.empty.hint`가 아직 "바로 저장/편집창 열기"로 표기. 이제 셋 다 *캡처 메뉴를 먼저* 띄우므로(해당 모드 프리셀렉트) 문구를 맞추면 좋음.
- 미해결 리스크: folder-as-truth라 bottle 폴더를 공용폴더로 바꾸면 남의 이미지도 그리드/ClearAll 대상 → Settings에 경고 표시는 해둠.
- 자체 오버레이 한계(추후 보강 여지): macOS 기본 ⇧⌘5에 있는 *창(window) 모드·돋보기 루페·선택영역 치수 표시*는 없음. 드래그 직사각형 선택만 지원. 멀티모니터는 전 화면 union 오버레이 1개로 처리(좌표 변환은 주 화면 기준 flip) — 모니터 배치가 특이하면 캡처 좌표 검증 필요.

### ✅ 최근 완료 (0.5.0 작업분)
- **🥒 이스터에그 burst**: 편집기 워터마크 텍스트가 *정확히* `pickle`/`피클`일 때 캔버스에 🥒가 솟구침(형 PizzaBurst 이식 → `Editor/PickleBurst.swift`). `EditorModel.pickleBurstID`+`maybeTriggerBurst` / `EditorView`의 `onChange(textWM.text)`로 발동.
- **캡처 동작 선택 + 자체 영역선택 오버레이 (⇧⌘5식)**: 단축키(S/D/A)를 누르면 **즉시** 전체화면 선택 오버레이(십자선)가 뜨고, 메뉴바 아래에 *해당 기능이 선택된* 컴팩트 모드바가 같이 뜸. 바로 드래그하면 그 기능으로 캡처 / 다른 기능은 모드바 클릭으로 변경 / **드래그 시작 순간 모드바 숨김**(캡처영역 안 가리게). ←/→ 모드변경, Esc/✕ 취소. 오버레이는 `sharingType=.none`라 캡처에 안 찍힘. 캡처는 `screencapture -R`(고정영역). (`Capture/RegionSelectController.swift`=오버레이창+뷰+컨트롤러, `Capture/CaptureModeBar.swift`=모드바, `CaptureService.captureRegionToFile/Clipboard`, `AppDelegate.presentCaptureMenu/runRegionCapture`)
- **캡처→메뉴바 빨려들기 애니메이션**: *저장(S)* 캡처 후 캡처 이미지가 **찍힌 그 자리에서** 줄어들며 메뉴바 아이콘으로 빨려들어가고 히스토리 팝업이 열림(`Capture/CaptureFlyAnimation.swift` → `AppDelegate.flourishAfterSave`). 자체 오버레이라 실제 캡처 좌표를 알아서 시작 위치가 정확함.
- **편집기 레이아웃 리디자인(1차)**: 상단 세그먼트 → **왼쪽 세로 아이콘 툴바**(펜·블러·워터마크+⌘Z) + **어두운 캔버스**(이미지 중앙·그림자)로 재구성. 창도 다크 외형+투명 타이틀바(`EditorWindowController`). 도구 옵션/저장·취소는 상단바로. (형태 우선, 세부는 추후)
- **이름 통일 → `PICkle`**: 섞여 있던 `PicKle`(대문자 K)·`PIC.kle`(점)을 화면·코드·파일명·DMG까지 전부 `PICkle`로. (번들 ID·Xcode 프로젝트/스킴/소스폴더 이름은 의도적으로 유지)
- **bottle 폴더명 → `PICkle bottle`**: `AppPaths.bottleFolderName`. 대소문자 차이라 기존 데이터 보존(대소문자 무시 파일시스템).
- **다국어(한/영 런타임 전환)**: `App/LocalizationManager.swift` + `Resources/{en,ko}.lproj/Localizable.strings`(키 93개). 선택 언어의 `.lproj` 번들을 직접 펴서 읽는 방식 → 재시작 없이 전환.
- **폴더아이콘 교체**: `guide/폴더아이콘.png`(피클병)·`guide/폴더아이콘_빈병.png`(빈병)을 1024 정사각으로 패딩해 `FolderIconFull/Empty.imageset` 교체.
- **빈 보관함 일러스트 교체**: `guide/빈폴더 안내.png`(8000²)를 512²로 최적화(1MB→70KB)해 `HistoryEmptyArt.imageset`. `HistoryView` emptyState에서 `Text("🥒")` → `Image("HistoryEmptyArt")`. (그림 속 문구 "THE FOLDER IS EMPTY"는 영어 고정, 아래 안내문은 다국어)
- **Sparkle 자동 업데이트(앱 측)**: 형 pizzaClip 패턴 이식. Sparkle 2.6.0 패키지 + Info.plist SU* 키(`SUFeedURL=https://pizza-clip.com/pickle/appcast.xml`, `SUPublicEDKey`=pizzaClip 키 재사용) + AppDelegate `SPUStandardUpdaterController` + "업데이트 확인…" 메뉴. 릴리스 스크립트에 Sparkle 헬퍼(XPC/Updater.app/Autoupdate) Developer ID 재서명 단계 추가(공증 통과 필수). appcast 생성: `scripts/sparkle-appcast.sh`. **호스팅 배포는 미완**(위 "다음" 참고).

---

## ✅ 2026-06-08 세션 완료 (편집기 UX 대수술 + 캡처 스페이스 이동)

> 아래 전부 **완료·실기검증·커밋**. 편집기 워터마크 입력칸은 여러 번 갈아엎은 끝에 **NSScrollView로 감싼 NSTextView**(세로 자동크기)로 안착 — 시행착오 교훈은 본문에.

### 캡처 — 스페이스바 영역 이동
- 드래그 중 **스페이스바 누른 채 이동 = 선택영역 통째 이동**(macOS ⇧⌘5식). `SelectionOverlayView`에 `isMoving`/`lastDragPoint`, `mouseDragged`에서 space 중엔 델타로 사각형+앵커 함께 이동(화면 밖 클램프, 엣지 드리프트 방지=앵커를 *적용된* 델타로 갱신). space 키는 `RegionSelectController.installKeyMonitor`의 로컬 모니터(`[.keyDown,.keyUp]`, keyCode 49)에서 잡아 **모든 오버레이에 `setMoving` 브로드캐스트**(드래그 오버레이가 key window가 아닐 수 있어서). 새 드래그마다 `isMoving=false` 초기화.

### 편집기 — 툴바 재설계 (시안 B: 떠있는 팝오버)
- 도구 옵션을 상단 바에서 빼서 **레일 아이콘 옆 떠있는 팝오버**(`optionsPopover`, 위치=`topBarHeight+1+railTopInset+toolIndex*toolSlot`). **마우스 떠나면 ~2초 후 페이드아웃**(`scheduleHidePopover`/`DispatchWorkItem`), 호버 유지(`keepPopover`), **선택 툴 재클릭=즉시 숨김 토글**(`selectTool`). 상단 바는 정보+취소/저장만(`topBarHeight=54`).
- 옵션 3종 세로 배치(`penControls`/`blurControls`/`watermarkControls` + `sliderRow` 헬퍼). 펜 색상은 `colorSwatch`/`widthDot`로 추출(LazyVGrid 타입체커 부담 완화).
- **워터마크 레일 아이콘 = 작은 "water mark" 텍스트**(`railWatermarkTool`). SF심볼 `textformat`이 한국어 macOS에서 "가가"로 보여서. **설정창 워터마크 탭 아이콘**도 `textformat`→`signature`.

### 편집기 — 캔버스에서 워터마크 직접 입력 (가장 고생한 부분)
- `CanvasTextEditor`(`NSViewRepresentable`) = **`NSScrollView`로 감싼 `NSTextView`**. `isVerticallyResizable=true`(세로 성장은 AppKit), `isHorizontallyResizable=false`+`widthTracksTextView=true`(폭은 SwiftUI가 hug 폭으로 고정 → 긴 줄 wrap 안 함, trailing newline 빈 줄 폭폭발 없음). 폭=`measure`(줄별 최대폭), `sizeThatFits`가 폭 책임+`hasMarkedText` IME 가드. Enter=줄바꿈, 캔버스 빈 곳 탭(투명 캐처)/Esc/포커스상실/도구전환=확정. `model.isEditingText`로 정적 `Text`↔편집기 스왑.
- ⚠️ **시행착오 교훈(반복 말 것)**: ①SwiftUI `TextField(axis:.vertical)`는 macOS에서 Return을 submit 처리·soft-wrap만 → 멀티라인 불가. ②bare NSTextView(resizable=false)는 SwiftUI가 매 키 입력마다 프레임 강제→`setFrameSize`가 **컨테이너/커서 리셋** 연쇄(커서 맨앞·둘째줄 안보임). ③매 키 `setAttributes(전체범위)`도 커서 리셋 → 스타일은 변경 시에만(`lastStyle` 비교). ④무한폭 컨테이너+trailing `\n`=폭폭발. **정석=ScrollView+verticallyResizable**(architect 자문 `ac8e86…`). 조합 중(`hasMarkedText`)엔 손 안 댐.
- **남은 후속(보류)**: 입력칸이 `canvasArea`의 `.scaleEffect(s)` 안에 있어 **한글 IME 후보창 좌표가 구조적으로 어긋남**. 안정화 확인됐으면 *편집칸만 scaleEffect 밖으로 빼서 좌표변환 배치*(`textWM.center*s`=화면좌표, 폰트는 이미 스케일된 크기).

### 편집기 — 정렬/자간/줄간격 (모델·미리보기·저장 일관)
- `TextWatermark`에 `tracking`/`lineSpacing`/`alignment(NSTextAlignment)` 추가. 미리보기 `Text`(`.kerning`/`.lineSpacing`/`.multilineTextAlignment`), 편집칸 NSTextView, 저장 렌더 `drawTextWatermark`(NSParagraphStyle `alignment`+`lineSpacing`, `.kern`, 멀티라인 `boundingRect`+`draw(with:)`) **모두 반영**. 슬라이더: 자간 `-12...20`, 줄간격 `0...24`. 로컬라이즈 키 추가 `editor.text.add/edit/tracking.help/linespacing.help`(en/ko), 고아 키 `label/placeholder` 제거.

### 편집기 — 배율(%) 표시
- 캔버스 fit-scale `s`를 `CanvasScaleKey`(PreferenceKey)로 위로 올려 `imageInfoBadge`에서 `displaySize.width*canvasScale/px.width*100`로 줌% 표시(창 리사이즈 실시간). 포인트 기준(레티나 풀스크린 캡처 ~30–50%); "실물 크기 기준" 원하면 backingScale 반영 가능.

### 산출물
- 툴바 시안 3종(A 2단레일/B 팝오버/C 아코디언): `docs/mockups/editor-toolbar-mockups.html`(+.png). 형이 B 선택.

---

## ✅ 2026-06-07 세션 완료 (캡처 파이프라인 재작성 + 편집기 개선)

> 직전 인계의 "캡처 안 됨" 최우선 버그를 포함해 아래 전부 **완료·실기검증**(사용자 멀티모니터 환경에서 직접 확인). 9갈래 어드버서리얼 코드리뷰로 추가 버그 8건도 수정. 다음 세션은 사용자가 새로 요청할 수정부터.

### 캡처 "안 됨" 버그 — 근본 원인이 3겹이었음 (★중요 교훈)
직전 인계의 가설(오버레이 key window)은 **부분적으로만** 맞았고, 실제로는 세 문제가 겹쳐 있었음:
1. **오버레이가 마우스 드래그를 못 받음** — accessory(LSUIElement) 앱은 `NSApp.activate`만으로 key window를 못 가짐. → 오버레이 창을 **`.nonactivatingPanel`** 로 만들어 앱 활성화 없이 마우스/키를 받게.
2. **`screencapture` 셸아웃이 화면기록 권한을 상속 못 받음** — `/usr/sbin/screencapture`를 `Process`로 띄우면 자식 프로세스라 PICkle의 TCC 권한을 못 써서 `could not create image from rect` 실패. (0.4.0의 `-i` 인터랙티브는 시스템이 사용자동의로 처리해 됐던 것 / 0.5.0의 `-R`은 안 됨.) → **ScreenCaptureKit(`SCScreenshotManager`)** 로 in-process 캡처. macOS 26에선 `CGWindowListCreateImage`도 **빈(검정) 이미지**만 반환하므로 SCK가 유일한 길.
3. **단일 union 오버레이 창이 한 모니터에만 렌더** → 메인 모니터에서 캡처 자체가 안 됨. → **화면별(per-screen) 오버레이**로 재작성(`NSScreen.screens` 각각에 창). commit 시 화면 로컬좌표 + `screen.frame.origin` → 글로벌 Cocoa 좌표.

### ⚠️ 디버깅 함정 (다음에 또 헤매지 말 것)
- **터미널/Claude에서 `open`으로 앱을 띄우면 화면기록 권한이 막힘** (responsible process가 터미널이 됨). 캡처는 **반드시 사용자가 Finder/Spotlight로 직접 실행**해야 권한이 PICkle 기준으로 평가됨. (이것 때문에 한참 "권한 있는데 빈 캡처" 헤맴.)
- `NSLog` 보간 문자열은 unified logging에서 `<private>`로 마스킹돼 `log show` grep에 안 잡힘 → 디버깅 땐 파일로 직접 기록. (지금은 다 제거됨.)
- LSUIElement는 computer-use/`open` allowlist에 안 잡히고, 오버레이는 `sharingType=.none`이라 스크린샷에도 안 찍힘 → 자동 검증 어려움.

### 함께 완료한 편집기/캡처 개선
- **편집기 왼쪽 툴바 클릭영역 확대**(`.contentShape(Rectangle())`) · **파란 포커스 링 제거**(`noFocusRing`/`focusEffectDisabled`).
- **워터마크 위치 스냅/가이드선**(9앵커, 임계 12pt) · **워터마크 크기 슬라이더 범위 `0.4...3`→`0.2...6`**.
- **편집기 캔버스 배경 = 체크무늬**(`CheckerboardBackground`, 검정 캡처 구분용) · **우측 상단 px/용량/확장자 배지**(`imageInfoBadge`, 크기는 `EditorModel.originalByteCount`로 1회 캐시).
- **맥 표준 십자선 커서**(커스텀 push/pop 폐기, `addCursorRect`/`cursorUpdate`).
- **리뷰가 잡은 버그 8건**: Esc/방향키 취소(`NSApp.activate` 추가) · **클립보드 캡처 Retina 2배 크기**(`rep.size`를 논리 포인트로) · 모니터 경계 넘는 드래그 클램프 · PNG 인코딩 백그라운드화(메인스레드 멈춤) · 배지 매프레임 디스크 stat 제거 · `NSScreen.main!` 강제언랩 가드 · 분수좌표 반올림 · 체크무늬 타일 크기.

### 핵심 파일 (캡처)
- `Capture/RegionSelectController.swift` — per-screen `.nonactivatingPanel` 오버레이 + `SelectionOverlayView`(드래그를 화면 bounds로 클램프) + 모드바 + Esc/←/→ 키모니터.
- `Capture/CaptureService.swift` — ScreenCaptureKit 캡처(`captureSCK`, 선택영역 중심이 속한 디스플레이 정확 매칭) + macOS13 Quartz fallback(`captureLegacy`). 옛 셸아웃 코드는 전부 제거됨.

---

## 0. 한 줄 정체성

**PICkle** = macOS 메뉴바 **스크린샷 캡처·편집·보관** 유틸리티.
형 앱 **pizzaClip(클립보드 히스토리)** 의 형제 — 구조·느낌은 같게, 테마는 🥒 **초록 피클**.

- 형: 텍스트(클립보드)를 모은다 → 동생: **스크린샷(이미지)를 모은다**.

---

## 1. 기능 전체

1. **자동 폴더** — `~/Documents/PICkle bottle` 자동 생성. 스크린샷은 데스크탑이 아니라 이 폴더에 저장.
2. **자동삭제** — 지정 기간 지난 파일 자동 휴지통(기본 30일, Settings 조절·끄기).
3. **단축키 3종** — `⇧⌥S` 일반 / `⇧⌥D` 기능(편집) / `⇧⌥A` 클립보드 복사(저장 안 함).
4. **편집창** — 펜 · 블러/모자이크(브러시+영역) · 워터마크(텍스트+로고 동시, 각각 드래그). ⌘Z 되돌리기.
5. **히스토리 창** — 🥒 병 아이콘 클릭 → 그리드 썸네일. 자물쇠/닫기, Clear all, Settings, 드래그앤드롭.
6. **다국어** — 한국어/영어 런타임 전환(Settings → 정보). 기본=시스템 언어.
7. **이스터에그** — (예정) 트리거 시 🥒 burst.

---

## 2. 확정된 설계 결정

| 결정 | 선택 | 이유 |
|---|---|---|
| 캡처 | **화면별 `.nonactivatingPanel` 오버레이**(⇧⌘5식) + **ScreenCaptureKit** in-process 캡처 | accessory 앱은 셸아웃 `screencapture`에 화면기록 권한이 안 넘어가고 macOS26은 `CGWindowListCreateImage`도 빈 이미지 → SCK가 유일. 단일 union 창은 메인 모니터에 안 떠서 화면별 오버레이로. (상세: ✅ 2026-06-07 세션 완료) |
| 저장 | **folder-as-truth** (DB 없음) | 스크린샷이 곧 실제 파일 → 드래그아웃/Finder 통합 거저. 메타데이터 필요해지면 그때 DB |
| 워터마크 | 텍스트 + 로고 **동시**, 각각 독립 | 이름/날짜 글자 + 브랜드 로고 둘 다, 위치·크기 따로 |
| 블러 | 가우시안+모자이크 / 브러시+영역 | 부분(브러시)·큰영역(드래그) 둘 다 |
| 자동삭제 | 기본 30일, 휴지통行 | 보관함 무한증가 방지 + 복구 가능 |
| 클립보드 캡처(A) | bottle 저장 안 함 | 빠른 1회성 복사·PizzaClip 연동 |
| 다국어 | `.lproj` 번들 직접 스위칭(`LocalizationManager`) | 재시작 없이 언어 전환. 일반 NSLocalizedString은 실행 중 못 바꿈 |
| 이름 표기 | 브랜드=`PICkle`, 번들ID/프로젝트명은 유지 | 화면 통일 + TCC 권한·프로젝트 구조 안정 |
| 서명 | Manual + Developer ID, 값은 `Signing.xcconfig`(로컬) | 안정 서명으로 TCC 권한 유지(§5) + 개인정보 비커밋 |
| App Sandbox | OFF (Hardened Runtime ON) | ScreenCaptureKit 화면기록 + 임의 경로 쓰기 때문 |

---

## 3. 아키텍처 골격 (형에서 물려받음)

**SwiftUI + AppKit 혼합, 메뉴바 전용(`LSUIElement=YES`)**.

- **Composition root**: `App/AppDelegate` 가 모든 wiring 허브 (상태바·옵저버·단축키·자동삭제·아이콘).
- **느슨한 연결**: `Notification.Name` 확장(`.pickle*`)으로 컴포넌트 통신.
- **저장**: folder-as-truth. `ScreenshotStore` 가 폴더를 직접 읽음.
- **다국어**: `App/LocalizationManager`(ObservableObject) + 전역 `L("key")`. 뷰는 `LocalizationManager.shared`를 관찰, 언어 바뀌면 `.id(loc.language)`로 리프레시.

```
PicKle/                # ← Xcode 소스폴더 이름은 그대로 PicKle (내부 식별자)
├── App/            # @main, AppDelegate(허브), AppPaths, Notifications, LocalizationManager
├── Capture/        # screencapture 호출(파일/클립보드), 권한 헬퍼
├── DesignSystem/   # Colors(피클그린), Theme(토큰)
├── Editor/         # EditorModel/View/WindowController (펜·블러·워터마크)
├── History/        # 패널·그리드·뷰모델·썸네일 로더
├── MenuBar/        # PickleIcon (빈병/피클병)
├── Settings/       # SettingsView (4탭, +언어 선택)
├── Shortcuts/      # KeyboardShortcuts 등록 (S/D/A)
├── Storage/        # ScreenshotStore, RetentionService, WatermarkPresets,
│                   #   FolderIcon, ClipboardService
└── Resources/      # Info.plist, entitlements, Assets.xcassets, {en,ko}.lproj/Localizable.strings
```

---

## 4. 디자인 시스템

피클 그린 `accent`: `#3B6B2F`(light) / `#6FAE4E`(dark). 패턴: `Color(light:dark:)` 적응형 쌍.
모양 토큰: `panelRadius=14`, `rowRadius=8`. 편집 캔버스는 최대 1000×640로 표시 스케일.

### 아이콘 자산 (`guide/`)
- 앱 아이콘: `피클 앱아이콘.png`(1024) → `AppIcon.appiconset`.
- 메뉴바: `상단메뉴바 아이콘.png`(피클병) / `메뉴바 아이콘 빈병.png`(빈병) → 18·36px 에셋. `isTemplate=false`.
- 폴더 아이콘: `폴더아이콘.png`(피클병) / `폴더아이콘_빈병.png`(빈병) → 1024 정사각으로 패딩 후 `FolderIconFull/Empty.imageset`, `NSWorkspace.setIcon`으로 bottle 폴더에 적용.

---

## 5. ⚠️ 코드 서명 & 권한(TCC)

**문제**: ad-hoc(무서명) 빌드는 빌드마다 코드 "지문"이 바뀜 → TCC가 매번 다른 앱으로 보고 Screen Recording 권한을 안 기억함(허용해도 무한 재요청).

**해결**: Manual + Developer ID 서명으로 지문 고정. 서명 값(팀ID·식별자)은 **`Signing.xcconfig`(gitignore)** 에 두고 `project.yml`의 `configFiles`로 참조 → 개인정보 비커밋 + 안정 서명.

**개발 워크플로우**:
- 항상 서명된 Release 빌드(`-configuration Release`, `CODE_SIGNING_ALLOWED=NO` 쓰지 말 것).
- `/Applications`에 `ditto` 설치해 실행. (산출물 이름이 `PICkle.app`이므로 옛 `PicKle.app`이 있으면 지우고 설치)
- 권한 꼬이면: `tccutil reset ScreenCapture com.Team-jAm.PICkle`.
- Screen Recording 권한 허용 후 앱 재시작 필요.
- 번들 ID 바꾸면 macOS가 새 앱으로 봐서 권한 1회 재부여 필요.

### 테스트 배포 DMG
- `scripts/release-test-dmg.sh` — Release 빌드를 ① 타임스탬프+하드닝 재서명 → ② 앱 공증(`notarytool`) → staple → ③ DMG 생성 → 서명 → ④ DMG 공증 → staple. 결과 `~/Downloads/PICkle-<버전>.dmg`.
- 서명 식별자·공증 키체인 프로필은 **`scripts/release.local.sh`(gitignore)** 에서 주입(`PICKLE_SIGN_IDENTITY` / `PICKLE_NOTARY_PROFILE`).
- 핵심 주의: xcodebuild 기본 서명은 `--timestamp=none`이라 공증 거부 → 스크립트가 `--timestamp`로 재서명함.

---

## 6. 버전 로드맵

- **0.1.0** ✅ 뼈대 + 빈 앱(메뉴바·폴더·패널 골격).
- **0.2.0** ✅ 캡처 + 저장(folder-as-truth) + 그리드.
- **0.3.0** ✅ 편집기(펜·워터마크·블러) + 공증 DMG.
- **0.4.0** ✅ 자동삭제 · Settings 4탭 · ⇧⌥A 클립보드 캡처 · 편집기 개선(탭 순서·⌘Z·텍스트+로고 동시) · 히스토리 자물쇠/닫기 · 빈병↔피클병 아이콘(메뉴바+폴더).
- **0.5.0** ⏳ (진행중) **이름 통일(PICkle)** ✅ · **다국어(한/영 런타임 전환)** ✅ · **폴더아이콘 교체** ✅ · bottle 폴더명 `PICkle bottle` ✅ · **빈 보관함 일러스트 교체** ✅ · **Sparkle 자동 업데이트(앱 측)** ✅ (호스팅은 1.0에서) · **🥒 이스터에그 burst** ✅ · **캡처 동작 선택 메뉴(메뉴 먼저)** ✅ · **메뉴바 빨려들기 애니메이션(S)** ✅ · **편집기 다크 레이아웃(1차)** ✅ · **편집기 팝오버 툴바(시안 B)** ✅ · **캔버스 직접 워터마크 입력** ✅ · **문단정렬·자간·줄간격** ✅ · **변 기준 스냅 가이드** ✅ · **배율% 표시** ✅ · **캡처 스페이스 이동** ✅.
  - ⚠️ `project.yml`의 `MARKETING_VERSION`은 아직 `0.4.0`. 0.5.0 릴리스 확정 시 올릴 것.

---

## 7. 협업 스타일
사용자는 바이브코더 → **쉬운 한국어**, 전문용어는 한 줄 풀이, 코드 바꿀 때 **"무엇을/왜"** 요약.
