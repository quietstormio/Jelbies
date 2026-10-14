//
//  RoomPreviewView.swift
//  DEBUG-only live preview of the room with RoomCamera (independent of the jelly renderer).
//

#if DEBUG
import SwiftUI
import MetalKit

struct RoomPreviewView: UIViewRepresentable {
    var theme = RoomTheme()

    func makeCoordinator() -> Coordinator { Coordinator(theme: theme) }

    func makeUIView(context: Context) -> MTKView {
        let v = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        v.colorPixelFormat = .bgra8Unorm_srgb
        v.depthStencilPixelFormat = .depth32Float
        v.sampleCount = 4
        v.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        v.delegate = context.coordinator
        context.coordinator.setup(v)
        return v
    }
    func updateUIView(_ uiView: MTKView, context: Context) { context.coordinator.room?.theme = theme }

    final class Coordinator: NSObject, MTKViewDelegate {
        var room: RoomRenderer?
        var queue: MTLCommandQueue?
        let theme: RoomTheme
        init(theme: RoomTheme) { self.theme = theme }
        func setup(_ v: MTKView) {
            guard let dev = v.device, let lib = dev.makeDefaultLibrary() else { return }
            queue = dev.makeCommandQueue()
            room = RoomRenderer(device: dev, library: lib, colorFormat: v.colorPixelFormat, depthFormat: v.depthStencilPixelFormat,
                                sampleCount: v.sampleCount, theme: theme)
        }
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
        func draw(in view: MTKView) {
            guard let room, let queue, let rpd = view.currentRenderPassDescriptor, let cmd = queue.makeCommandBuffer(),
                  let enc = cmd.makeRenderCommandEncoder(descriptor: rpd), let drawable = view.currentDrawable else { return }
            let s = view.drawableSize
            let cam = RoomCamera.viewProj(aspect: Float(s.width / max(s.height, 1)))
            room.encode(enc, viewProj: cam.viewProj, camPos: cam.eye, lightViewProj: nil, shadowTex: nil)
            enc.endEncoding()
            cmd.present(drawable)
            cmd.commit()
        }
    }
}

#Preview { RoomPreviewView().ignoresSafeArea() }
#endif
