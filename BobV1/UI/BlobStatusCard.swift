import SwiftUI

struct BlobStatusCard: View {
    var blob: BlobState
    var onClose: () -> Void = {}

    var body: some View {
        let b = blob.breed
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                BlobPlaceholder(breed: b, look: blob.look, mood: blob.mood).frame(width: 70, height: 70)
                VStack(alignment: .leading, spacing: 2) {
                    Text(blob.name).font(UITheme.title(24))
                    Text("\(blob.personality.displayName) \(b.spec.displayName)")
                        .font(UITheme.caption(14)).foregroundStyle(b.deep)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .bold, design: .rounded))
                        .frame(width: 44, height: 44).background(Circle().fill(UITheme.panelDeep.opacity(0.7)))
                }
                .accessibilityLabel("Close")
            }
            Text("Feeling \(blob.mood.rawValue.lowercased())")
                .font(UITheme.body(17))
                .padding(.horizontal, 14).padding(.vertical, 5)
                .background(Capsule().fill(b.light.opacity(0.45)))
            VStack(spacing: 8) {
                row("fork.knife", "Tummy", blob.hungerLevel.rawValue, blob.hunger)
                row("drop.fill", "Thirst", blob.thirstLevel.rawValue, blob.thirst)
                row("bubbles.and.sparkles.fill", "Cleanliness", blob.cleanLevel.rawValue, blob.clean)
            }
            hearts
        }
        .foregroundStyle(UITheme.ink)
        .padding(18)
        .frame(maxWidth: 340)
        .softPanel(radius: 30)
        .accessibilityElement(children: .contain)
    }

    private func row(_ icon: String, _ label: String, _ word: String, _ v: Double) -> some View {
        HStack {
            Image(systemName: icon).frame(width: 24).foregroundStyle(blob.breed.core)
            Text(label).font(UITheme.body(15))
            Spacer()
            Text(word).font(UITheme.body(15))
            Circle().fill(v >= 0.45 ? Color.green.opacity(0.65) : v >= 0.2 ? Color.orange : Color.red.opacity(0.7))
                .frame(width: 9, height: 9)
        }
        .accessibilityElement(children: .combine)
    }

    private var hearts: some View {
        let filled = Int((blob.affection * 5).rounded())
        return HStack(spacing: 6) {
            ForEach(0..<5, id: \.self) { i in
                Image(systemName: i < filled ? "heart.fill" : "heart")
                    .foregroundStyle(i < filled ? Color.pink.opacity(0.8) : UITheme.inkSoft)
            }
        }
        .font(.system(size: 22))
        .accessibilityLabel("Affection \(filled) of 5 hearts")
    }
}

#Preview("Status") {
    let s = PreviewSupport.store(blobs: 2)
    return ZStack { HUDPlaceholderStage(); BlobStatusCard(blob: s.blobs[1]) }
}
