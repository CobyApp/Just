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
                } header: {
                    Text("Apple Music")
                } footer: {
                    Text("Apple Music은 API 키 없이 동작합니다. 검색 횟수 제한도 없습니다.")
                }

                Section {
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
