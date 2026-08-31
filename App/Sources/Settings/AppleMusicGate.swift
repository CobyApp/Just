import JustDesign
import JustMusic
import SwiftUI

/// What the browse screen shows when Apple Music access is missing.
///
/// The three reasons access can be absent need three different actions, and the
/// previous single "허용하기" button was only correct for one of them: once the
/// user has denied the prompt, iOS never shows it again, so tapping the button
/// did nothing at all and the app looked broken.
struct AppleMusicGate: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        } actions: {
            VStack(spacing: JustTheme.Space.snug) {
                switch app.access {
                case .notDetermined:
                    Button("Apple Music 허용하기") {
                        Task { await app.requestAccess() }
                    }
                    .buttonStyle(.justPrimary)
                case .denied:
                    Button("설정 열기") { openSystemSettings() }
                        .buttonStyle(.justPrimary)
                    Button("다시 확인") {
                        Task { await app.refreshAccess() }
                    }
                    .buttonStyle(.justSecondary)
                case .restricted, .authorized:
                    Button("다시 확인") {
                        Task { await app.refreshAccess() }
                    }
                    .buttonStyle(.justPrimary)
                }
            }
        }
    }

    private var title: String {
        switch app.access {
        case .notDetermined: "Apple Music 연결"
        case .denied: "접근이 거부되어 있습니다"
        case .restricted: "기기 제한으로 사용할 수 없습니다"
        case .authorized: "연결 확인이 필요합니다"
        }
    }

    private var symbol: String {
        switch app.access {
        case .notDetermined: "music.note"
        case .denied, .restricted: "lock"
        case .authorized: "arrow.clockwise"
        }
    }

    private var message: String {
        switch app.access {
        case .notDetermined:
            "곡 검색과 재생에 Apple Music을 씁니다. 계정 정보는 기기를 벗어나지 않고, 가사 해석도 기기 안에서 처리됩니다."
        case .denied:
            "iOS는 한 번 거부한 권한을 앱에서 다시 물어볼 수 없습니다. 설정 > Just에서 '미디어 및 Apple Music'을 켠 뒤 돌아와 주세요."
        case .restricted:
            "스크린 타임이나 기기 관리 정책으로 Apple Music 접근이 제한되어 있습니다."
        case .authorized:
            "접근은 허용되어 있습니다. 카탈로그 연결만 다시 확인해 보세요."
        }
    }

    /// Deep-links to this app's page in Settings, where the media toggle lives.
    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}
