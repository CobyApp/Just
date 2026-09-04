import JustDesign
import JustMusic
import JustSensei
import SwiftUI
// Same reason as JustSensei's wrapper: TranslationSession is not
// Sendable-audited, so the download call below reads as sending it.
@preconcurrency import Translation

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

    @State private var plainTranslationOn = PlainTranslator.shared.isEnabled
    @State private var asksEveryTime = AnalysisDepthPreference.asksEveryTime
    @State private var packStatus: LanguageAvailability.Status?
    /// Non-nil while a download is being asked for.
    @State private var download: TranslationSession.Configuration?

    /// Says what the fallback will actually do on this device, which depends on
    /// both the model and the language pack.
    private var translationFooter: String {
        guard plainTranslationOn else {
            return "AI가 번역하지 못한 줄은 번역 없이 단어만 남습니다."
        }
        switch packStatus {
        case .installed:
            return "AI가 번역하지 못한 줄은 간단 번역으로 채웁니다. 직역에 가깝고 문법 설명은 없습니다."
        case .supported:
            return "간단 번역을 쓰려면 한국어 번역 파일을 한 번 받아야 합니다."
        case .unsupported:
            return "이 기기에서는 간단 번역을 쓸 수 없습니다."
        case nil:
            return "간단 번역을 쓸 수 있는지 확인하고 있습니다."
        @unknown default:
            return "간단 번역을 쓸 수 있는지 확인하고 있습니다."
        }
    }

    /// What the chosen mode will do, or why the choice is not on offer.
    private var depthFooter: String {
        guard app.sensei.usesOnDeviceModel else {
            return "이 기기에서는 AI 번역을 쓸 수 없어 빠른 번역으로만 동작합니다."
                + " \(AnalysisDepth.quick.detail)\(translationCaveat)"
        }
        return app.sensei.depth.detail + translationCaveat
    }

    /// Said where the choice is made, because the two settings depend on each
    /// other and sit in the same section without knowing it.
    ///
    /// Quick analysis gets its sentences from the system translator and nowhere
    /// else. With the switch off or the pack missing it produces dictionary
    /// meanings and no translation at all — while the text above promises to
    /// 「곡 전체를 몇 초 안에 채웁니다」. Deep analysis is unaffected: the model
    /// writes its own.
    private var translationCaveat: String {
        let usesTranslatorForSentences = !app.sensei.usesOnDeviceModel
            || app.sensei.depth == .quick
        guard usesTranslatorForSentences else { return "" }

        if !plainTranslationOn {
            return "\n\n지금은 「간단 번역으로 채우기」가 꺼져 있어 문장 번역이 나오지 않습니다."
        }
        if packStatus == .supported {
            return "\n\n문장 번역을 보려면 아래에서 한국어 번역 파일을 받아 주세요."
        }
        if packStatus == .unsupported {
            return "\n\n이 기기에서는 간단 번역을 쓸 수 없어 문장 번역이 나오지 않습니다."
        }
        return ""
    }

    var body: some View {
        NavigationStack {
            ZStack {
                JustBrandBackground()
                Form {
                Section {
                    JustScreenHeader("설정", subtitle: "나에게 맞는 공부 리듬")
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 12, trailing: 0))
                }
                if let problem = app.connectionProblem {
                    Section {
                        Text(problem.message)
                            .font(JustTheme.Font.caption)
                            .foregroundStyle(JustTheme.Feedback.warning)
                        Button(problem.actionTitle) { problem.act(openURL: openURL, app: app) }
                    } header: {
                        Label("Apple Music 연결 문제", systemImage: "exclamationmark.triangle")
                    }
                }

                Section("복습") {
                    Picker("하루 목표", selection: Binding(
                        get: { app.dailyGoal },
                        set: { app.dailyGoal = $0 }
                    )) {
                        ForEach(AppModel.dailyGoalChoices, id: \.self) { count in
                            Text("\(count)개").tag(count)
                        }
                    }
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
                            .foregroundStyle(JustTheme.Feedback.warning)
                    }
                }

                Section {
                    // The choice worth putting first, and the only one on this
                    // screen the reader will feel immediately: it is the
                    // difference between a song being ready in seconds and in
                    // minutes.
                    Picker("번역 방식", selection: Binding(
                        get: { app.sensei.depth },
                        set: {
                            app.sensei.depth = $0
                            AnalysisDepthPreference.chosen = $0
                        }
                    )) {
                        ForEach(AnalysisDepth.allCases) { depth in
                            Text(depth.title).tag(depth)
                        }
                    }
                    .disabled(!app.sensei.usesOnDeviceModel)

                    if app.sensei.usesOnDeviceModel {
                        Toggle("곡을 열 때마다 묻기", isOn: Binding(
                            get: { asksEveryTime },
                            set: { asksEveryTime = $0; AnalysisDepthPreference.asksEveryTime = $0 }
                        ))
                    }

                    Picker("자동 해석", selection: Binding(
                        get: { app.autoAnalysis },
                        set: { app.autoAnalysis = $0 }
                    )) {
                        ForEach(AutoAnalysisPolicy.allCases) { policy in
                            Text(policy.title).tag(policy)
                        }
                    }
                    Toggle("간단 번역으로 채우기", isOn: Binding(
                        get: { plainTranslationOn },
                        set: {
                            plainTranslationOn = $0
                            PlainTranslator.shared.isEnabled = $0
                            // Turning it back on after it gave up should try
                            // again rather than stay quietly off.
                            if $0 { PlainTranslator.shared.reconsider() }
                        }
                    ))

                    if plainTranslationOn, packStatus == .supported {
                        // The pack can only be fetched from a view, and it puts
                        // a system prompt on screen — so it is asked for here,
                        // by someone who opened this screen, rather than in the
                        // middle of an analysis run.
                        Button("한국어 번역 파일 받기") {
                            download = PlainTranslator.configuration
                        }
                    }
                } header: {
                    Text("가사 해석")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(depthFooter)
                        Text(app.autoAnalysis.detail)
                        // Quick mode *is* the system translator, so a note
                        // about what happens when the model falls back to it
                        // would be describing a fallback that cannot occur.
                        if app.sensei.depth == .deep {
                            Text(translationFooter)
                        }
                    }
                }

                Section {
                    DisclosureGroup("정보") {
                        LabeledContent("번역 방식", value: app.engineLabel)
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
                    // Reworded when ads arrived. The claim about lyrics and
                    // study records is still exactly true, but "전부 기기
                    // 안에서" as a blanket statement stopped being — the ad on
                    // the wait screen reaches Google. Saying so is the point:
                    // a privacy note that is quietly wrong is worse than none.
                    Text("가사 해석은 기기 안에서 처리됩니다. 가사 원문이나 학습 기록은 어디로도 올라가지 않습니다. 곡을 준비하는 동안 보이는 광고는 Google을 거치며, 맞춤 광고는 쓰지 않습니다.")
                }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("")
            .translationTask(download) { session in
                // Downloads on first use and then answers; either way the
                // status is re-read so the row stops offering what is done.
                try? await session.prepareTranslation()
                // The translator decided this device could not translate before
                // the pack arrived. It has to be told that changed, or the
                // download the reader just asked for does nothing until the
                // app is launched again.
                PlainTranslator.shared.reconsider()
                packStatus = await PlainTranslator.shared.availability()
                download = nil
            }
            .task { packStatus = await PlainTranslator.shared.availability() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
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
