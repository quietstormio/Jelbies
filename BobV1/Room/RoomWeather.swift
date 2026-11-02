//
//  RoomWeather.swift
//  The storm as the window shader sees it (Melon/Weather.swift is the storm itself). Two float4: w = rain, flash, time, gloom; w2 = flash spot (0...1 across the
//  screen), 0, render width, render height in px. All zero = clear weather: the shader paths are exactly the old ones.
//

import simd

struct WeatherGPU: Equatable {
    var w = SIMD4<Float>(repeating: 0)
    var w2 = SIMD4<Float>(repeating: 0)

    init() {}
    init(look: WeatherLook, time: Float, width: Int, height: Int) {
        guard !look.isClear else { return }
        w = SIMD4(look.rain, look.flash, time.truncatingRemainder(dividingBy: 600), look.gloom)
        w2 = SIMD4(look.spot, 0, Float(width), Float(height))
    }
    var isClear: Bool { w.x + w.y + w.w <= 0.001 }
}
