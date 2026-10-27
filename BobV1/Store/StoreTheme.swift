//
//  StoreTheme.swift
//  The look of the places-to-go UI (Town, Shop, Bag, Track): the palette, the rounded heavy fonts, the pills, and the 3D thumbnails of the goods.
//  Thumbnails are the real meshes (foods, shoes) drawn once by SceneKit offscreen and cached; scenes with no 3D object (soaps, trick pages) use a clean
//  icon card. These are UI only: everything that appears in the room is a real 3D mesh.
//

import SwiftUI
import SceneKit
import simd

extension Color {
    init(hex: UInt32) { self.init(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255) }
}

enum SK {
    static let cream = Color(hex: 0xF7F0E0)
    static let ink = Color(hex: 0x4D331F)
    static let muted = Color(hex: 0x6B5749)
    static let sky = Color(hex: 0x6EB3D1)
    static let pink = Color(hex: 0xE98AA4)
    static let honey = Color(hex: 0xFFE07A)
    static let honeyDeep = Color(hex: 0xF9CC59)
    static let mint = Color(hex: 0x9FD9B0)
    static let card = Color.white.opacity(0.78)
    /// Follows Dynamic Type (capped at 2x, see A11yFont.swift); a mid-session size change applies on the next re-render.
    static func font(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font { JFont.scaled(size, weight) }
    static let shadow = Color(red: 0.3, green: 0.2, blue: 0.12)

    /// "3h 20m", "25m", "40s".
    static func timeLeft(_ s: TimeInterval) -> String {
        let m = Int((s / 60).rounded(.up))
        if s < 60 { return "\(max(Int(s), 1))s" }
        if m < 60 { return "\(m)m" }
        let h = m / 60, r = m % 60
        return r == 0 ? "\(h)h" : "\(h)h \(r)m"
    }
    /// Condition points shown on a card: a nudge of 0.10 reads "+2".
    static func points(_ v: Float) -> Int { max(1, Int((v * 20).rounded())) }
}

/// The Drops balance: a drop icon and the count.
struct DropsPill: View {
    let wallet: DropsWallet
    var dark = false
    var glass = false          // Liquid Glass capsule (home HUD)
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "drop.fill").font(.system(size: 15, weight: .black)).foregroundStyle(dark ? SK.honey : SK.sky)
            Text("\(wallet.count)").font(SK.font(17, .black)).foregroundStyle(dark ? SK.cream : SK.ink).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 14).frame(minHeight: 44)
        .modifier(DropsPillBack(dark: dark, glass: glass))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(wallet.count) Drops")
        .accessibilityIdentifier("drops-pill")
    }
}

private struct DropsPillBack: ViewModifier {
    let dark: Bool, glass: Bool
    func body(content: Content) -> some View {
        if glass {
            content.hudFrost(in: .capsule)
        } else {
            content
                .background(Capsule().fill(dark ? SK.ink : SK.cream).shadow(color: SK.shadow.opacity(0.2), radius: 5, y: 2))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.5), lineWidth: 1))
        }
    }
}

/// A perk as a small chip: icon (+ time left).
struct PerkChip: View {
    let kind: PerkKind
    var left: TimeInterval?
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: kind.symbol).font(.system(size: 11, weight: .heavy))
            Text(left.map { "\(kind.title) \(SK.timeLeft($0))" } ?? kind.title).font(SK.font(11, .heavy)).lineLimit(1)
        }
        .foregroundStyle(SK.ink)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(SK.honey))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(left.map { "\(kind.title), \(SK.timeLeft($0)) left" } ?? kind.title)
    }
}

/// The wavy lower edge of the shop header.
struct WavyBottom: SwiftUI.Shape {
    var amplitude: CGFloat = 7
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: .zero)
        p.addLine(to: CGPoint(x: r.maxX, y: 0))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - amplitude))
        let n = 6, w = r.width / CGFloat(n)
        for i in 0..<n {
            let x1 = r.maxX - CGFloat(i) * w
            p.addQuadCurve(to: CGPoint(x: x1 - w, y: r.maxY - amplitude),
                           control: CGPoint(x: x1 - w / 2, y: r.maxY - amplitude + (i % 2 == 0 ? amplitude * 2 : -amplitude * 2)))
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - 3D thumbnails

@MainActor
enum StoreThumb {
    private static var cache: [String: UIImage] = [:]
    private static var device = MTLCreateSystemDefaultDevice()

    /// The mesh a store item is drawn with (nil = an icon card).
    static func mesh(for item: StoreItem) -> RoomMesh? {
        if let f = item.food, let c = Consumables.with(id: f) {
            return c.pizzaLayout && c.piece == nil ? DiningModels.heldSlice(scale: 1.25, palette: c.palette) : DiningModels.heldPiece(c, index: 0, scale: 1.25)
        }
        if let w = item.wear { return w.isShoe ? shoeMesh(w) : WearMeshes.restMesh(w) }
        if let d = item.decor { return DecorModels.thumbnail(d) }
        return nil
    }

    /// A shoe on a foot (the body-coloured bean, the shell round it), foot-local, a pair seen from the front-left.
    static func shoeMesh(_ look: WearLook) -> RoomMesh {
        let b = RoomMeshBuilder(); b.material = .plain
        let bean = FootBean.localF
        let n = ShoeModel.normals(bean)
        let base = UInt32(b.mesh.vertices.count)
        let body = OKLab.srgbToLinear(SIMD3(0.50, 0.68, 0.95))
        for i in bean.indices { b.vertex(bean[i], n[i], ao: 1, color: body) }
        var t = 0
        while t + 2 < ShoeModel.tris.count { b.triangle(base + ShoeModel.tris[t], base + ShoeModel.tris[t + 1], base + ShoeModel.tris[t + 2]); t += 3 }
        ShoeModel.build(look, bean: bean, floorY: -10, time: 1.3, side: 0, into: b)
        return b.mesh
    }

    static func geometry(_ m: RoomMesh) -> SCNGeometry {
        func srgb(_ x: Float) -> Float { powf(max(x, 0), 1 / 2.2) }
        let pos = m.vertices.map { SCNVector3($0.pos.x, $0.pos.y, $0.pos.z) }
        let nrm = m.vertices.map { SCNVector3($0.normal.x, $0.normal.y, $0.normal.z) }
        var col: [Float] = []
        col.reserveCapacity(m.vertices.count * 4)
        for v in m.vertices { col += [srgb(v.color.x), srgb(v.color.y), srgb(v.color.z), 1] }
        let colData = col.withUnsafeBufferPointer { Data(buffer: $0) }
        let colSrc = SCNGeometrySource(data: colData, semantic: .color, vectorCount: m.vertices.count, usesFloatComponents: true, componentsPerVector: 4,
                                       bytesPerComponent: 4, dataOffset: 0, dataStride: 16)
        let idx = m.indices.withUnsafeBufferPointer { Data(buffer: $0) }
        let el = SCNGeometryElement(data: idx, primitiveType: .triangles, primitiveCount: m.indices.count / 3, bytesPerIndex: 4)
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: pos), SCNGeometrySource(normals: nrm), colSrc], elements: [el])
        let mat = SCNMaterial()
        mat.lightingModel = .lambert
        mat.diffuse.contents = UIColor.white
        mat.isDoubleSided = true
        g.materials = [mat]
        return g
    }

    /// The cached thumbnail of a mesh (one render per key).
    static func image(_ key: String, mesh: RoomMesh, size: CGFloat = 200, yaw: Float = 0.6, pitch: Float = 0.5) -> UIImage? {
        if let c = cache[key] { return c }
        guard !mesh.vertices.isEmpty, let device else { return nil }
        let scene = SCNScene()
        let node = SCNNode(geometry: geometry(mesh))
        var lo = SIMD3<Float>(repeating: .infinity), hi = SIMD3<Float>(repeating: -.infinity)
        for v in mesh.vertices { let p = SIMD3(v.pos.x, v.pos.y, v.pos.z); lo = simd_min(lo, p); hi = simd_max(hi, p) }
        let c = (lo + hi) / 2, r = max(simd_length(hi - lo) / 2, 0.01)
        node.pivot = SCNMatrix4MakeTranslation(c.x, c.y, c.z)
        node.eulerAngles = SCNVector3(0, yaw, 0)
        scene.rootNode.addChildNode(node)
        let cam = SCNNode(); cam.camera = SCNCamera()
        cam.camera?.fieldOfView = 30
        cam.camera?.zNear = 0.01; cam.camera?.zFar = 20
        let dist = r / sinf(15 * .pi / 180) * 1.02
        cam.position = SCNVector3(0, dist * sinf(pitch), dist * cosf(pitch))
        cam.eulerAngles = SCNVector3(-pitch, 0, 0)
        scene.rootNode.addChildNode(cam)
        let amb = SCNNode(); amb.light = SCNLight(); amb.light?.type = .ambient; amb.light?.intensity = 430; amb.light?.color = UIColor(white: 1, alpha: 1)
        scene.rootNode.addChildNode(amb)
        let sun = SCNNode(); sun.light = SCNLight(); sun.light?.type = .directional; sun.light?.intensity = 660
        sun.eulerAngles = SCNVector3(-0.9, 0.7, 0)
        scene.rootNode.addChildNode(sun)
        scene.background.contents = UIColor.clear
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.pointOfView = cam
        let img = renderer.snapshot(atTime: 0, with: CGSize(width: size, height: size), antialiasingMode: .multisampling4X)
        cache[key] = img
        return img
    }

    /// The view of an item's thumbnail (yaw about the model, pitch above it). Most use one angle; the taco is seen from its open end so the U of the shell
    /// and the fillings in it read.
    static func angles(for item: StoreItem) -> (yaw: Float, pitch: Float) {
        if let w = item.wear { return w.slot == .face || w.slot == .head ? (0.5, 0.2) : w.slot == .hands ? (0.9, 0.3) : (0.6, 0.25) }
        if item.decor != nil { return (0.5, 0.5) }
        if item.id == "taco" { return (0.38, 0.42) }
        return (0.55, 0.42)
    }
    static func image(for item: StoreItem) -> UIImage? {
        if let r = item.room { return UIImage(named: "room_thumb_\(r.rawValue)") }
        guard let m = mesh(for: item) else { return nil }
        let a = angles(for: item)
        return image(item.id, mesh: m, yaw: a.yaw, pitch: a.pitch)
    }
}

/// A store item's picture: the 3D thumbnail, else an icon card.
struct ItemArt: View {
    let item: StoreItem
    var size: CGFloat = 96
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous).fill(tint)
            if let img = StoreThumb.image(for: item) {
                Image(uiImage: img).resizable().scaledToFit().padding(size * 0.06)
            } else {
                Image(systemName: UIImage(systemName: item.symbol) != nil ? item.symbol : "star.fill")
                    .font(.system(size: size * 0.42, weight: .heavy)).foregroundStyle(SK.ink.opacity(0.85))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
    private var tint: Color {
        switch item.kind {
        case .food: return SK.honey.opacity(0.55); case .treat: return SK.pink.opacity(0.35); case .supply: return SK.sky.opacity(0.35)
        case .trickPage: return SK.mint.opacity(0.55); case .shoes: return SK.sky.opacity(0.28); case .wear: return SK.pink.opacity(0.25); case .decor: return SK.honey.opacity(0.4); case .room: return SK.honey.opacity(0.3)
        }
    }
}
