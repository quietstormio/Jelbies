//
//  GpuCal.metal
//  Fixed-cost calibration kernels for -GpuCal 1 (see GpuCal.swift): one ALU-bound, one memory-bound. Never used otherwise.
//
#include <metal_stdlib>
using namespace metal;

kernel void calAlu(device float *out [[buffer(0)]], uint tid [[thread_position_in_grid]]) {
    float a = float(tid) * 1e-4f + 0.5f, b = a + 0.1f, c = a + 0.2f, d = a + 0.3f;
    for (int i = 0; i < 1536; i++) {
        a = fma(a, 0.9993f, 0.00071f); b = fma(b, 0.9991f, 0.00053f);
        c = fma(c, 0.9989f, 0.00037f); d = fma(d, 0.9997f, 0.00011f);
    }
    out[tid] = a + b + c + d;
}

kernel void calMem(device const float4 *src [[buffer(0)]], device float4 *dst [[buffer(1)]], uint tid [[thread_position_in_grid]]) {
    dst[tid] = src[tid] * 1.0001f + src[(tid * 7u + 13u) & 524287u] * 0.5f;
}
