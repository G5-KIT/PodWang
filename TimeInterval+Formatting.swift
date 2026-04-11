// TimeInterval+Formatting.swift v3.2
// Utility extension on TimeInterval for human-readable playback durations.
// Kept in its own file so it can be used anywhere without importing view layers.

import Foundation

extension TimeInterval {

    /// Formats a duration in seconds as h:mm:ss or m:ss.
    /// Returns "0:00" for invalid values (NaN, infinite).
    var formattedAsPlaybackTime: String {
        guard !isNaN && !isInfinite else { return "0:00" }
        let total = Int(self)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}
