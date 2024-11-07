//
//  RenderPass.swift
//  VimKit
//
//  Created by Kevin McKee
//

import MetalKit

protocol RenderPass {

    var label: String { get }

    var renderPassDescriptor: MTLRenderPassDescriptor? { get }

    func draw(commandBuffer: MTLCommandBuffer)
}
