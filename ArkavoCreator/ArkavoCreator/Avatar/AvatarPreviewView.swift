//
//  AvatarPreviewView.swift
//  ArkavoCreator
//
//  Created for VRM Avatar Integration (#140)
//

import Metal
import MetalKit
import SwiftUI

/// SwiftUI wrapper for MTKView to display VRM avatar
struct AvatarPreviewView: NSViewRepresentable {
    let renderer: VRMAvatarRenderer
    let backgroundColor: Color

    func makeNSView(context _: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.delegate = renderer
        mtkView.preferredFramesPerSecond = 60
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false

        // Set background color (convert to RGB colorspace first)
        if let rgbColor = NSColor(backgroundColor).usingColorSpace(.deviceRGB) {
            mtkView.clearColor = MTLClearColor(
                red: Double(rgbColor.redComponent),
                green: Double(rgbColor.greenComponent),
                blue: Double(rgbColor.blueComponent),
                alpha: Double(rgbColor.alphaComponent),
            )
        } else {
            // Fallback to green if conversion fails
            mtkView.clearColor = MTLClearColor(red: 0, green: 1, blue: 0, alpha: 1)
        }

        // Enable depth testing
        mtkView.depthStencilPixelFormat = .depth32Float

        return mtkView
    }

    func updateNSView(_ nsView: MTKView, context _: Context) {
        // Update background color (convert to RGB colorspace first)
        if let rgbColor = NSColor(backgroundColor).usingColorSpace(.deviceRGB) {
            nsView.clearColor = MTLClearColor(
                red: Double(rgbColor.redComponent),
                green: Double(rgbColor.greenComponent),
                blue: Double(rgbColor.blueComponent),
                alpha: Double(rgbColor.alphaComponent),
            )
        }
    }
}

// MARK: - Preview

#Preview {
    if let device = MTLCreateSystemDefaultDevice(),
       let renderer = VRMAvatarRenderer(device: device)
    {
        AvatarPreviewView(renderer: renderer, backgroundColor: .green)
            .frame(width: 640, height: 480)
    } else {
        Text("Metal not available")
    }
}
