import Foundation
import JustCore

extension Error {
    /// The network, not the song: no connection, or one too slow to answer.
    var isOffline: Bool {
        guard let url = self as? URLError else { return false }
        switch url.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut,
             .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
             .dataNotAllowed, .internationalRoamingOff:
            return true
        default:
            return false
        }
    }
}

enum PlaybackFailure {
    /// What to tell the reader when neither a video nor the clip would play.
    /// A network that let them down is theirs to fix; a song with nothing to
    /// play is not.
    static func message(videoError: (any Error)?, previewError: any Error) -> String {
        if let failure = previewError as? ITunesCatalog.Failure, case .transport(let message) = failure {
            return message
        }
        if previewError.isOffline || videoError?.isOffline == true {
            return "인터넷 연결이 불안정해 곡을 불러오지 못했습니다. 연결을 확인한 뒤 다시 열어 주세요."
        }
        return ITunesCatalog.Failure.noPreview.localizedDescription
    }
}
