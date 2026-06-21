import Foundation

struct DVRescueMedia {
    var totalFrames: Int = 0
    var errorFrames: Int = 0
    var audioErrors: Int = 0
    var timecodeBreaks: Int = 0
    var dropouts: Int = 0
    var recordingDates: [String] = []
    var duration: TimeInterval = 0
    var lastTimecode: String = ""
}

// Incrementally parses dvrescue XML from a streaming stdin pipe.
// dvrescue emits XML line by line; we scan the text buffer for complete
// <frame> elements rather than waiting for a valid closing root tag.
class DVRescueXMLParser {
    private(set) var media = DVRescueMedia()
    private var buffer = ""
    private var processedFrames = 0
    private var prevTimecode = ""

    var onUpdate: ((DVRescueMedia) -> Void)?

    func feed(data: Data) {
        guard let str = String(data: data, encoding: .utf8) else { return }
        buffer += str
        scanNewFrames()
    }

    func finalize(fps: Double = 29.97) {
        scanNewFrames()
        media.duration = Double(media.totalFrames) / fps
    }

    func reset() {
        media = DVRescueMedia()
        buffer = ""
        processedFrames = 0
        prevTimecode = ""
    }

    // MARK: - Private

    private func scanNewFrames() {
        // Scan for complete <frame ...> or <frame .../> blocks
        var searchStart = buffer.startIndex

        while let frameStart = buffer.range(of: "<frame ", range: searchStart..<buffer.endIndex) {
            // Find end of this element (self-closing or paired close tag)
            guard let elementEnd = findFrameEnd(from: frameStart.lowerBound) else { break }

            let frameSlice = String(buffer[frameStart.lowerBound..<elementEnd])
            parseFrameSlice(frameSlice)
            processedFrames += 1
            searchStart = elementEnd
        }

        // Trim buffer to avoid unbounded growth; keep the last partial element
        if searchStart > buffer.startIndex {
            buffer = String(buffer[searchStart...])
        }
        if buffer.count > 512_000 { buffer = "" }
    }

    private func findFrameEnd(from start: String.Index) -> String.Index? {
        // Self-closing: <frame ... />
        if let sc = buffer.range(of: "/>", range: start..<buffer.endIndex),
           let openClose = buffer.range(of: "<frame ", range: start..<sc.lowerBound) {
            // Make sure no nested <frame starts between our frame and the />
            let between = buffer[openClose.upperBound..<sc.lowerBound]
            if !between.contains("<frame ") {
                return sc.upperBound
            }
        }

        // Paired: <frame ...> ... </frame>
        if let closeTag = buffer.range(of: "</frame>", range: start..<buffer.endIndex) {
            return closeTag.upperBound
        }
        return nil
    }

    private func parseFrameSlice(_ slice: String) {
        media.totalFrames += 1

        // Extract timecode
        if let tc = attributeValue(key: "tc", in: slice) {
            if !prevTimecode.isEmpty && tc < prevTimecode { media.timecodeBreaks += 1 }
            prevTimecode = tc
            media.lastTimecode = tc
        }

        // Recording date
        if let rdt = attributeValue(key: "rdt", in: slice) {
            if !media.recordingDates.contains(rdt) { media.recordingDates.append(rdt) }
        }

        // Error presence — dvrescue marks degraded frames
        if attributeValue(key: "n", in: slice) != nil {
            // Count <sta> child elements indicating errors
            let staMatches = slice.components(separatedBy: "<sta ").dropFirst()
            for sta in staMatches {
                let t = attributeValue(key: "t", in: "<sta \(sta)") ?? ""
                // t=10 is audio, others are video/data errors
                if t == "10" { media.audioErrors += 1 }
                else { media.errorFrames += 1 }
            }

            // Count dropouts via <dseq>
            let dseqMatches = slice.components(separatedBy: "<dseq ").dropFirst()
            for dseq in dseqMatches {
                if let dStr = attributeValue(key: "n", in: "<dseq \(dseq)"),
                   let d = Int(dStr), d > 0 { media.dropouts += d }
            }
        }

        onUpdate?(media)
    }

    private func attributeValue(key: String, in xml: String) -> String? {
        let patterns = ["\(key)=\"([^\"]+)\"", "\(key)='([^']+)'"]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
               let range = Range(match.range(at: 1), in: xml) {
                return String(xml[range])
            }
        }
        return nil
    }
}
