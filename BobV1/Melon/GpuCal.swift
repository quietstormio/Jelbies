//
//  GpuCal.swift
//  `-GpuCal 1`: a fixed-cost GPU workload timed every frame, plus thermal-state transitions and queue-wait of the real frame, all reported in the
//  PerfMeter `ctx:` line (MelonRenderer.takePerfContext). Reading it: if `cal` (the same tiny kernels, always the same work) slows down together
//  with the frame, the GPU itself is slower (clocks / thermal duty cycle / another process); if `cal` stays flat while the frame slows, the cause
//  is in our frame (a stall, bandwidth, an upload); if `qwait` grows, the frame sat in the queue behind someone else's GPU work.
//

import Foundation
import Metal
import QuartzCore

nonisolated final class GpuCalibrator: @unchecked Sendable {
    private let alu: MTLComputePipelineState, mem: MTLComputePipelineState
    private let aluOut: MTLBuffer, memA: MTLBuffer, memB: MTLBuffer
    private let lock = NSLock()
    private var aluMs: [Double] = [], memMs: [Double] = []
    private static let aluThreads = 65536, memThreads = 524288

    init?(device: MTLDevice, library: MTLLibrary) {
        guard let fa = library.makeFunction(name: "calAlu"), let fm = library.makeFunction(name: "calMem"),
              let pa = try? device.makeComputePipelineState(function: fa), let pm = try? device.makeComputePipelineState(function: fm),
              let o = device.makeBuffer(length: Self.aluThreads * 4, options: .storageModePrivate),
              let a = device.makeBuffer(length: Self.memThreads * 16, options: .storageModePrivate),
              let b = device.makeBuffer(length: Self.memThreads * 16, options: .storageModePrivate) else { return nil }
        alu = pa; mem = pm; aluOut = o; memA = a; memB = b
        o.label = "cal alu out"; a.label = "cal mem src"; b.label = "cal mem dst"
    }

    /// Two tiny command buffers (own queue slots, committed right behind the frame): their own gpuStart/EndTime are the calibration.
    func submit(on queue: MTLCommandQueue) {
        if let c = queue.makeCommandBuffer(), let e = c.makeComputeCommandEncoder() {
            c.label = "cal alu"
            e.setComputePipelineState(alu); e.setBuffer(aluOut, offset: 0, index: 0)
            e.dispatchThreads(MTLSize(width: Self.aluThreads, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 256, height: 1, depth: 1))
            e.endEncoding()
            c.addCompletedHandler { [weak self] c in self?.add(alu: (c.gpuEndTime - c.gpuStartTime) * 1000) }
            c.commit()
        }
        if let c = queue.makeCommandBuffer(), let e = c.makeComputeCommandEncoder() {
            c.label = "cal mem"
            e.setComputePipelineState(mem); e.setBuffer(memA, offset: 0, index: 0); e.setBuffer(memB, offset: 0, index: 1)
            e.dispatchThreads(MTLSize(width: Self.memThreads, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 256, height: 1, depth: 1))
            e.endEncoding()
            c.addCompletedHandler { [weak self] c in self?.add(mem: (c.gpuEndTime - c.gpuStartTime) * 1000) }
            c.commit()
        }
    }
    private func add(alu t: Double) { lock.lock(); aluMs.append(t); lock.unlock() }
    private func add(mem t: Double) { lock.lock(); memMs.append(t); lock.unlock() }

    /// "cal[alu 0.31/0.45 mem 0.52/0.80 ms mean/p95 n=118]" since the last call.
    func take() -> String {
        lock.lock(); let a = aluMs.sorted(), m = memMs.sorted(); aluMs = []; memMs = []; lock.unlock()
        func s(_ x: [Double]) -> String { x.isEmpty ? "-" : String(format: "%.2f/%.2f", x.reduce(0, +) / Double(x.count), x[min(x.count - 1, Int(Double(x.count) * 0.95))]) }
        return "cal[alu \(s(a)) mem \(s(m)) ms mean/p95 n=\(a.count)]"
    }
}

/// Queue wait of the real frame: commit -> gpuStart (the GPU picked it up) and commit -> kernelStart. Contention from another process, or our own
/// frames in flight, shows up here. Mean / p95 / max per window.
nonisolated final class QueueWaitStats: @unchecked Sendable {
    private let lock = NSLock()
    private var gpu: [Double] = [], kernel: [Double] = []
    func add(gpuWait: Double, kernelWait: Double) { lock.lock(); gpu.append(gpuWait * 1000); kernel.append(kernelWait * 1000); lock.unlock() }
    func take() -> String {
        lock.lock(); let g = gpu.sorted(), k = kernel.sorted(); gpu = []; kernel = []; lock.unlock()
        guard !g.isEmpty else { return "" }
        func s(_ x: [Double]) -> String { String(format: "%.1f/%.1f/%.1f", x.reduce(0, +) / Double(x.count), x[min(x.count - 1, Int(Double(x.count) * 0.95))], x.last!) }
        return "qwait[commit->gpuStart \(s(g)) commit->kernelStart \(s(k)) ms mean/p95/max]"
    }
}

/// ProcessInfo.thermalState transitions with their time since launch; `take()` = the current state plus the changes since the last call.
nonisolated final class ThermalLog: @unchecked Sendable {
    private let lock = NSLock()
    private let t0 = CACurrentMediaTime()
    private var changes: [String] = []
    private var token: NSObjectProtocol?
    init() {
        record(ProcessInfo.processInfo.thermalState, initial: true)
        token = NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: nil) { [weak self] _ in
            self?.record(ProcessInfo.processInfo.thermalState, initial: false)
        }
    }
    deinit { if let token { NotificationCenter.default.removeObserver(token) } }
    static func name(_ s: ProcessInfo.ThermalState) -> String {
        switch s { case .nominal: return "nominal"; case .fair: return "fair"; case .serious: return "serious"; case .critical: return "critical"; @unknown default: return "?" }
    }
    private func record(_ s: ProcessInfo.ThermalState, initial: Bool) {
        lock.lock(); changes.append(String(format: "%@@+%.1fs", Self.name(s), CACurrentMediaTime() - t0)); lock.unlock()
    }
    func take() -> String {
        lock.lock(); let c = changes; changes = []; lock.unlock()
        let now = Self.name(ProcessInfo.processInfo.thermalState)
        return c.isEmpty ? "thermal \(now)" : "thermal \(now) (changes \(c.joined(separator: ", ")))"
    }
}
