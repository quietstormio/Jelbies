import Foundation

enum PreviewSupport {
    /// A GameStore backed by a temp file, pre-filled with `blobs` Blobs.
    static func store(blobs: Int) -> GameStore {
        let url = FileManager.default.temporaryDirectory.appending(path: "preview-\(UUID().uuidString).json")
        let s = GameStore(fileURL: url)
        let breeds = BreedID.allCases
        for i in 0..<min(blobs, 3) {
            let c = KennelGenerator.candidates(for: breeds[i], seed: UInt64(10 + i))[i]
            try? s.adopt(candidate: c, name: ["Mochi", "Pudding", "Pip"][i])
        }
        return s
    }
}
