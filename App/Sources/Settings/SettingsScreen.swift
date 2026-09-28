import RingRingCore
import RingRingDesign
import RingRingMusic
import RingRingSensei
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
    @State private var packStatus: LanguageAvailability.Status?
    /// Non-nil while a download is being asked for.
    @State private var download: TranslationSession.Configuration?

    /// Says what the line study will show on this device, which depends on the
    /// switch and the language pack.
    private var translationFooter: String {
        guard plainTranslationOn else {
            return "문장 번역을 끄면 각 줄에 단어 뜻과 문법만 표시됩니다."
        }
        switch packStatus {
        case .installed:
            return "각 줄을 단어 뜻·문법과 함께 문장으로 번역합니다."
        case .supported:
            return "문장 번역을 보려면 번역 파일을 한 번 받아야 합니다."
        case .unsupported:
            return "이 기기에서는 문장 번역을 쓸 수 없어 단어 뜻만 표시됩니다."
        case nil:
            return "문장 번역을 쓸 수 있는지 확인하고 있습니다."
        @unknown default:
            return "문장 번역을 쓸 수 있는지 확인하고 있습니다."
        }
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
                Section {
                    // Also picked with the heart on a group's page; here so
                    // it can be changed or cleared without finding that page.
                    NavigationLink {
                        OshiPicker()
                    } label: {
                        LabeledContent {
                            Text(app.oshi?.name ?? String(localized: "없음"))
                        } label: {
                            Label("최애 그룹", systemImage: "crown.fill")
                        }
                    }
                } header: {
                    Text("최애")
                } footer: {
                    Text("최애 그룹은 홈 맨 위에 걸리고, 탭과 위젯이 그 그룹 색으로 바뀝니다.")
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
                    Toggle("복습 알림", isOn: Binding(
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
                        Text("알림 권한이 거부되어 있습니다. 설정 > 알림 > 링링에서 켜 주세요.")
                            .font(JustTheme.Font.caption)
                            .foregroundStyle(JustTheme.Feedback.warning)
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
                    Toggle("문장 번역", isOn: Binding(
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
                        // by someone who opened this screen.
                        Button("번역 파일 받기") {
                            download = PlainTranslator.configuration
                        }
                    }
                } header: {
                    Text("가사 해석")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(app.autoAnalysis.detail)
                        Text(translationFooter)
                    }
                }

                Section {
                    Button("닫은 안내 다시 보기") { GuideDismissals.shared.restoreAll() }
                        .disabled(GuideDismissals.shared.dismissed.isEmpty)
                } header: {
                    Text("안내")
                } footer: {
                    Text("화면마다 있는 안내 카드는 ✕로 닫을 수 있습니다. 닫은 안내는 여기서 되살립니다.")
                }

                // Required where Google's consent form applies (EEA, UK): the
                // reader must be able to change the answer they gave at launch.
                if AdsConsent.shared.isPrivacyOptionsRequired {
                    Section {
                        Button("광고 개인정보 설정") {
                            Task { await AdsConsent.shared.presentPrivacyOptions() }
                        }
                    } header: {
                        Text("광고")
                    }
                }

                Section {
                    DisclosureGroup("정보") {
                        LabeledContent("번역 방식", value: app.engineLabel)
                        LabeledContent("곡 정보", value: "iTunes")
                        LabeledContent("영상", value: "YouTube")
                        LabeledContent("가사", value: "LRCLIB")
                        LabeledContent("재생", value: app.playbackLabel)
                    }
                } footer: {
                    // Reworded when ads arrived. The claim about lyrics and
                    // study records is still exactly true, but "전부 기기
                    // 안에서" as a blanket statement stopped being — the ad on
                    // the wait screen reaches Google. Saying so is the point:
                    // a privacy note that is quietly wrong is worse than none.
                    Text("가사 해석은 기기 안에서 처리됩니다. 가사 원문이나 학습 기록은 어디로도 올라가지 않습니다. 노래 영상은 YouTube에서 재생되고, 곡을 준비하는 동안 보이는 광고는 Google을 거치며, 맞춤 광고는 쓰지 않습니다.")
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
            // The bar keeps its material: with it hidden, rows scrolled up
            // under the 「닫기」 button and their values disappeared behind it.
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}

/// Every group under its label, with its colour — a plain list rather than a
/// navigation-link `Picker`, which drew the section headers as more rows to
/// pick.
private struct OshiPicker: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                row(title: String(localized: "없음"), color: nil, isSelected: app.oshiID == nil) { app.oshiID = nil }
            }
            ForEach(IdolGroup.Label.allCases, id: \.self) { label in
                Section(label.localizedTitle) {
                    ForEach(IdolGroup.all.filter { $0.label == label }) { group in
                        row(title: group.name, color: group.memberColor, isSelected: app.isOshi(group)) {
                            app.oshiID = group.id
                        }
                    }
                }
            }
        }
        .navigationTitle("최애 그룹")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(title: String, color: Color?, isSelected: Bool, pick: @escaping () -> Void) -> some View {
        Button {
            pick()
            Haptics.tick()
            dismiss()
        } label: {
            HStack(spacing: JustTheme.Space.snug) {
                Circle()
                    .fill(color ?? .clear)
                    .overlay { Circle().strokeBorder(color == nil ? JustTheme.Ink.tertiary : .white, lineWidth: 2) }
                    .frame(width: 18, height: 18)
                Text(title).foregroundStyle(JustTheme.Ink.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").fontWeight(.bold).foregroundStyle(color ?? JustTheme.Kawaii.accent)
                }
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
