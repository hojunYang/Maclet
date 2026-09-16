# Maclet 코드 구조

Maclet은 **기능 코드는 `Features`에 모으고**, 앱 전체를 연결하는 코드만 `AppShell`과 `State`에 두는 구조입니다.

## 폴더 지도

```text
Sources/
├── MacletApp/
│   ├── AppShell/                 앱 실행, 메뉴바/창 표시, NSAlert
│   ├── DesignSystem/             여러 기능이 공유하는 SwiftUI 스타일과 컴포넌트
│   ├── Features/
│   │   ├── Timer/                타이머 상태, 입력, 팝오버, 프리셋 설정
│   │   ├── KeepDisplayOn/        Keep Display On과 caffeinate 프로세스
│   │   ├── KeepAwake/            Keep Awake와 pmset 처리
│   │   ├── CleanKeyboard/        키보드 차단 화면과 이벤트 필터
│   │   ├── Clipboard/            클립보드 읽기/쓰기, 기록 UI
│   │   ├── Commands/             명령 목록, 편집기, 빠른 실행 버튼
│   │   ├── GlobalShortcut/       전역 단축키 등록과 설정 UI
│   │   ├── Startup/              로그인 시 실행 설정
│   │   ├── Logs/                 명령 실행 기록 UI
│   │   ├── CommandCenter/        기능 모듈을 메뉴바 팝오버에 배치
│   │   └── Settings/             기능별 설정 패널을 한 화면에 배치
│   ├── Services/                 여러 기능이 같이 쓰는 관리자 권한 실행
│   └── State/AppState.swift      기능 상태와 앱 화면 사이를 연결하는 중앙 조정자
└── MacletCore/                   UI에 의존하지 않는 저장 모델, JSON 저장소, 명령 실행
```

테스트도 `Tests/MacletAppTests/<Feature>` 형태로 기능 폴더를 따라갑니다.

## 타이머 코드는 어디에 있나

| 파일 | 책임 |
| --- | --- |
| `Features/Timer/CountdownTimerManager.swift` | 실행·일시정지·재개·완료 상태와 시간 문자열 |
| `Features/Timer/TimerModule.swift` | 메뉴바 팝오버의 타이머 UI |
| `Features/Timer/TimerDurationFields.swift` | 시·분·초 키보드 입력 UI |
| `Features/Timer/TimerPresetSettings.swift` | Features의 Timer 아래에 항상 표시되는 프리셋 추가·수정·정렬·삭제 |
| `MacletCore/AppSettings.swift` | 프리셋을 `settings.json`에 저장하는 데이터 형식 |
| `AppShell/AppPresentationCoordinator.swift` | 타이머와 Keep Display On 중 메뉴바에 표시할 시간을 결정 |

타이머 시작부터 완료 알림까지의 흐름은 다음과 같습니다.

```text
TimerModule
  → AppState.startTimer
  → CountdownTimerManager
  → AppState.alert
  → AlertWindowController
  → NSAlert
```

`AppState`는 기능 구현을 직접 가지는 곳이 아니라 화면과 기능 객체를 연결하는 곳입니다. 기능 동작을 바꿀 때는 먼저 해당 `Features/<Feature>` 폴더를 보고, 다른 기능과 연결되는 지점만 `AppState`에서 찾으면 됩니다.

## 자주 수정할 위치

- 메뉴바 팝오버 배치 변경: `Features/CommandCenter/CommandCenterView.swift`
- 설정 화면의 패널 순서 변경: `Features/Settings/SettingsScreen.swift`
- 메뉴바 아이콘과 남은 시간 우선순위 변경: `AppShell/AppPresentationCoordinator.swift`
- 공용 색상·글래스 스타일 변경: `DesignSystem/CommandCenterComponents.swift`
- 저장 형식 변경: `MacletCore/AppSettings.swift`와 `MacletCore/CommandRepository.swift`

새 기능을 추가할 때는 `Features/<FeatureName>` 폴더 안에 동작 객체와 UI를 함께 만들고, `CommandCenterView` 또는 `SettingsScreen`에서는 그 기능 뷰를 배치만 합니다. 둘 이상의 기능에서 실제로 재사용할 때만 `DesignSystem`이나 `Services`로 올립니다.

Feature의 화면 제목과 코드 기준 이름은 동일하게 유지합니다. 현재 기준은 `Timer`, `KeepDisplayOn`, `KeepAwake`, `CleanKeyboard`, `Clipboard`, `QuickCommands`이며, 예전 저장값인 `preventSleep`과 `disableSleep`은 `AppSettings`의 호환 디코더에서만 취급합니다.
