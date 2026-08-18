import JustDesign
import JustSensei
import SwiftUI

struct SettingsScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("접근 권한") {
                        Text(app.access.label)
                            .foregroundStyle(JustTheme.Ink.secondary)
                    }
                    LabeledContent("구독") {
                        Text(app.canPlayFullTracks ? "전곡 재생 가능" : "미리듣기만 가능")
                            .foregroundStyle(JustTheme.Ink.secondary)
                    }
                    if app.access != .authorized {
                        Button("접근 허용하기") {
                            Task { await app.requestAccess() }
                        }
                    }
                    LabeledContent("카탈로그 연결") {
                        Text(app.catalogStatus.label)
                            .foregroundStyle(
                                app.catalogStatus == .ok ? JustTheme.Ink.secondary : .orange
                            )
                    }
                    if let advice = app.catalogStatus.advice {
                        Text(advice)
                            .font(JustTheme.Font.caption)
                            .foregroundStyle(.orange)
                    }
                    Button("연결 확인") {
                        Task { await app.checkCatalog() }
                    }
                } header: {
                    Text("Apple Music")
                } footer: {
                    Text("Apple Music은 API 키 없이 동작합니다. 검색 횟수 제한도 없습니다.")
                }

                Section {
                    Toggle("매일 복습 알림", isOn: Binding(
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
                } header: {
                    Text("복습")
                } footer: {
                    Text("복습 간격은 FSRS로 계산합니다. 알림을 켜두면 그날 올라온 카드를 놓치지 않습니다.")
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
                    Text(app.autoAnalysis.detail)
                        .font(JustTheme.Font.caption)
                        .foregroundStyle(JustTheme.Ink.tertiary)

                    LabeledContent("해석 엔진") {
                        Text(app.sensei.usesOnDeviceModel ? "Apple Intelligence" : "사전 (오프라인)")
                            .foregroundStyle(JustTheme.Ink.secondary)
                    }
                    if let unavailability = app.sensei.unavailability {
                        Text(unavailability.message)
                            .font(JustTheme.Font.caption)
                            .foregroundStyle(JustTheme.Ink.secondary)
                    }
                } header: {
                    Text("일본어 해석")
                } footer: {
                    Text("가사 해석은 전부 기기 안에서 처리됩니다. 가사 원문이나 학습 기록이 서버로 올라가지 않습니다.")
                }

                Section {
                    LabeledContent("음악 · 앨범 정보", value: "Apple Music")
                    LabeledContent("가사", value: "LRCLIB")
                } header: {
                    Text("데이터 출처")
                } footer: {
                    Text("Apple Music API는 가사를 제공하지 않아, 싱크 가사는 공개 데이터베이스인 LRCLIB에서 가져옵니다.")
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

}
