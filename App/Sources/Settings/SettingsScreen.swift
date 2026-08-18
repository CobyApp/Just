import JustDesign
import JustMusic
import JustSensei
import SwiftUI

/// Settings, cut down to what a user actually decides.
///
/// The previous version listed every piece of state the app knew — access,
/// subscription, catalog, engine, sources — which read as a diagnostics dump.
/// Status now shows up only when something is wrong and needs an action; the
/// rest is folded into one "정보" group that can stay closed.
struct SettingsScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Form {
                if let problem = app.connectionProblem {
                    Section {
                        Text(problem.message)
                            .font(JustTheme.Font.caption)
                            .foregroundStyle(.orange)
                        Button(problem.actionTitle) { problem.act(openURL: openURL, app: app) }
                    } header: {
                        Label("Apple Music 연결 문제", systemImage: "exclamationmark.triangle")
                    }
                }

                Section("복습") {
                    Toggle("매일 알림", isOn: Binding(
                        get: { app.reminder.isEnabled },
                        set: { app.reminder.isEnabled = $0 }
                    ))
                    if app.reminder.isEnabled {
                        DatePicker(
                            "알림 시각",
                            selection: Binding(
                                get: { app.reminder.timeAsDate },
                                set: { app.reminder.setTime(from: $0) }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                    }
                    if app.reminder.isDenied {
                        Text("알림 권한이 거부되어 있습니다. 설정 > 알림 > Just에서 켜 주세요.")
                            .font(JustTheme.Font.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    Picker("자동 해석", selection: Binding(
                        get: { app.autoAnalysis },
                        set: { app.autoAnalysis = $0 }
                    )) {
                        ForEach(AutoAnalysisPolicy.allCases) { policy in
                            Text(policy.title).tag(policy)
                        }
                    }
                } header: {
                    Text("가사 해석")
                } footer: {
                    Text(app.autoAnalysis.detail)
                }

                Section {
                    DisclosureGroup("정보") {
                        LabeledContent("해석 엔진", value: app.engineLabel)
                        LabeledContent("음악 · 앨범", value: "Apple Music")
                        LabeledContent("가사", value: "LRCLIB")
                        LabeledContent("재생", value: app.playbackLabel)
                        if let unavailability = app.sensei.unavailability {
                            Text(unavailability.message)
                                .font(JustTheme.Font.caption)
                                .foregroundStyle(JustTheme.Ink.secondary)
                        }
                    }
                } footer: {
                    Text("가사 해석은 전부 기기 안에서 처리됩니다. 가사 원문이나 학습 기록이 서버로 올라가지 않습니다.")
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
            .task { await app.refreshAccess() }
        }
        .presentationDetents([.large])
    }
}
