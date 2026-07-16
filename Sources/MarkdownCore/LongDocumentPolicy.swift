import Foundation

/// Shared thresholds for features that should switch to progressive work.
public enum LongDocumentPolicy {
    public static let utf8ByteThreshold = 512 * 1024
    public static let lineThreshold = 10_000

    public static func isLongDocument(_ text: String) -> Bool {
        if text.utf8.count >= utf8ByteThreshold {
            return true
        }
        return lineCount(in: text, stoppingAt: lineThreshold) >= lineThreshold
    }

    public static func isLongDocument(utf8ByteCount: Int, lineCount: Int) -> Bool {
        utf8ByteCount >= utf8ByteThreshold || lineCount >= lineThreshold
    }

    public static func lineCount(in text: String, stoppingAt limit: Int? = nil) -> Int {
        guard !text.isEmpty else { return 0 }
        var count = 1
        var previousWasCarriageReturn = false
        for byte in text.utf8 {
            if byte == 0x0D {
                count += 1
                previousWasCarriageReturn = true
            } else {
                if byte == 0x0A, !previousWasCarriageReturn {
                    count += 1
                }
                previousWasCarriageReturn = false
            }
            if let limit, count >= limit {
                return count
            }
        }
        return count
    }
}
