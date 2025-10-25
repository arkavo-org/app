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

        // Set background color
        let nsColor = NSColor(backgroundColor)
        mtkView.clearColor = MTLClearColor(
            red: Double(nsColor.redComponent),
            green: Double(nsColor.greenComponent),
            blue: Double(nsColor.blueComponent),
            alpha: Double(nsColor.alphaComponent),
        )

        // Enable depth testing
        mtkView.depthStencilPixelFormat = .depth32Float

        return mtkView
    }

    func updateNSView(_ nsView: MTKView, context _: Context) {
        // Update background color
        let nsColor = NSColor(backgroundColor)
        nsView.clearColor = MTLClearColor(
            red: Double(nsColor.redComponent),
            green: Double(nsColor.greenComponent),
            blue: Double(nsColor.blueComponent),
            alpha: Double(nsColor.alphaComponent),
        )
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
