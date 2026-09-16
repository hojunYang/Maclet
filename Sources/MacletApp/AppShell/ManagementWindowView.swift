import SwiftUI

struct ManagementWindowView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Maclet")
                    .font(.title2.weight(.bold))
                Spacer()
                Button {
                    appState.beginAddCommand()
                } label: {
                    Label("Add Command", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            Picker("View", selection: $appState.selectedTab) {
                ForEach(MainTab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.symbolName)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)

            Group {
                switch appState.selectedTab {
                case .commands:
                    CommandListView()
                case .logs:
                    RunLogView()
                case .settings:
                    SettingsScreen()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(18)
        .frame(width: 720, height: 560)
        .foregroundStyle(MacletSystemColors.label)
        .background(MacletSystemColors.windowBackground)
        .macletModals()
    }
}
