//
//  Renderer.swift
//  OsmMetal
//
//  Created by Roope on 2.3.2024.
//

import Foundation
import Metal
import MetalKit
import simd

struct FrameConstants {
    var view: float4x4
    var projection: float4x4
}

struct OsmConstants {
    var isBuilding: simd_int1
}

class Renderer: NSObject {

    /// In range [0, 1], 1 meaning a full 360 degrees.
    public var rotation: Float = 0

    /// Inverse camera distance from origin. I.e., 0 is furthest.
    public var zoom: Float = 0

    private static let maxOutstandingFrameCount = 3

    private let device: MTLDevice!
    private let commandQueue: MTLCommandQueue!
    private let mtkView: MTKView!
    private var renderPipelineState: MTLRenderPipelineState!
    private var depthStencilState: MTLDepthStencilState!
    private var vertexBuffer: MTLBuffer!
    private var vertexDescriptor: MTLVertexDescriptor!

    private var frameIndex = 0

    private var constantsBuffer: MTLBuffer!
    private let constantsBufferLength = MemoryLayout<FrameConstants>.size * maxOutstandingFrameCount
    private var constantsBufferOffset = 0

    private var osmConstantsBuffer: MTLBuffer!
    private let osmConstantsBufferLength = MemoryLayout<OsmConstants>.size * maxOutstandingFrameCount
    private var osmConstantsBufferOffset = 0

    private var frameSemaphore = DispatchSemaphore(value: maxOutstandingFrameCount)

    private var time: TimeInterval = 0.0

    private var nodeCoords: [simd_float2] = []
    /// [id: index]
    private var nodeIndices: [Int: UInt16] = [:]

    private let nodesBuffer: MTLBuffer

    /// Generic ways
    private var wayNodeIndexBuffers: [(indexCount: Int, buffer: MTLBuffer)] = []

    /// Building ways
    private var buildingNodeIndexBuffers: [(indexCount: Int, buffer: MTLBuffer)] = []

    // swiftlint:disable:next function_body_length
    init(device: MTLDevice!, view: MTKView, nodes: [Osm.Node], bounds: Osm.Bounds, ways: [Osm.Way]) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()
        self.mtkView = view

        self.constantsBuffer = device.makeBuffer(length: constantsBufferLength, options: .storageModeShared)
        self.osmConstantsBuffer = device.makeBuffer(length: osmConstantsBufferLength, options: .storageModeShared)

        // MARK: Init nodes

        nodeCoords = Array(repeating: simd_float2(0, 0), count: nodes.count)

        let aspectRatio = bounds.aspectRatio

        // A degree of longitude approaches zero in distance when approaching the poles,
        // while a degree of latitude is always the same distance
        let meanLat = (bounds.maxlat + bounds.minlat) * 0.5
        let lonScale = cos(meanLat * .pi / 180)

        for node in nodes {
            let lon = node.lon.rescale(
                from: (min: bounds.minlon, max: bounds.maxlon),
                to: (min: -1, max: 1)
            ) // longitude over x = west left, east right

            let lat = node.lat.rescale(
                from: (min: bounds.minlat, max: bounds.maxlat),
                to: (min: 1 / aspectRatio, max: -1 / aspectRatio)
            ) // latitude over z, reversed = north away, south toward

            nodeCoords[node.index] = simd_float2(Float(lon * lonScale), Float(lat))
            nodeIndices[node.id] = UInt16(node.index)
        }

        let length = MemoryLayout<simd_float2>.size * nodes.count
        guard let buffer = device.makeBuffer(length: length, options: .storageModeShared) else {
            fatalError()
        }
        self.nodesBuffer = buffer
        self.nodesBuffer.contents().copyMemory(from: &nodeCoords, byteCount: length)

        // MARK: Init ways

        for way in ways {
            var indices: [UInt16] = []
            for nd in way.nds {
                if let index = nodeIndices[nd.ref] {
                    indices.append(index)
                }
            }

            let length = MemoryLayout<UInt16>.size * indices.count
            guard let buffer = device.makeBuffer(length: length, options: .storageModeShared) else {
                fatalError()
            }
            buffer.contents().copyMemory(from: indices, byteCount: length)

            let wayBuffer = (indexCount: indices.count, buffer: buffer)

            if way.isBuilding {
                self.buildingNodeIndexBuffers.append(wayBuffer)
            } else {
                self.wayNodeIndexBuffers.append(wayBuffer)
            }
        }

        super.init()

        view.device = device
        view.delegate = self

        view.clearColor = MTLClearColor(red: 38/255, green: 47/255, blue: 47/255, alpha: 1.0)
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float

        view.sampleCount = 4

        makeVertexDescriptor()
        makePipeline()
    }

    func makeVertexDescriptor() {
        vertexDescriptor = MTLVertexDescriptor()

        let attr = vertexDescriptor.attributes
        attr[0].format = .float2
        attr[0].offset = 0
        attr[0].bufferIndex = 0

        let layouts = vertexDescriptor.layouts
        layouts[0].stride = MemoryLayout<simd_float2>.stride
    }

    func makePipeline() {
        guard let library = device.makeDefaultLibrary() else {
            fatalError()
        }

        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineDescriptor.vertexFunction = library.makeFunction(name: "vertex_main")
        renderPipelineDescriptor.fragmentFunction = library.makeFunction(name: "fragment_main")
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
        renderPipelineDescriptor.depthAttachmentPixelFormat = mtkView.depthStencilPixelFormat
        renderPipelineDescriptor.vertexDescriptor = vertexDescriptor
        renderPipelineDescriptor.rasterSampleCount = mtkView.sampleCount

        do {
            renderPipelineState = try device.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
        } catch {
            fatalError()
        }

        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.isDepthWriteEnabled = true
        depthStencilDescriptor.depthCompareFunction = .less

        guard let state = device.makeDepthStencilState(descriptor: depthStencilDescriptor) else {
            fatalError()
        }
        depthStencilState = state
    }
}

// MARK: - Constants

extension Renderer {

    func updateFrameConstants() {
        let rotationRadians = self.rotation * 2 * .pi
        let rotation = simd_float4x4(rotateY: rotationRadians)

        let zoomFactor = 1 - self.zoom

        let cameraFrom = simd_float3(0, zoomFactor * 1, zoomFactor * 1)

        let camera = simd_float4x4(lookAt: simd_float3(0, 0, 0),
                                   from: cameraFrom,
                                   up: simd_float3(0, 1, -1))

        let view = camera.inverse * rotation

        let aspectRatio = Float(mtkView.drawableSize.width / mtkView.drawableSize.height)

        let projection = simd_float4x4(perspectiveProjectionFoVY: .pi / 3,
                                       aspectRatio: aspectRatio,
                                       near: 0.01,
                                       far: 100)

        var constants = FrameConstants(view: view, projection: projection)

        let size = MemoryLayout<FrameConstants>.size

        constantsBufferOffset += size
        if constantsBufferOffset >= constantsBufferLength {
            constantsBufferOffset = 0
        }

        let pointer = constantsBuffer.contents().advanced(by: constantsBufferOffset)

        pointer.copyMemory(from: &constants, byteCount: size)
    }

    func updateOsmConstants(isBuilding: Bool) {
        var constants = OsmConstants(isBuilding: isBuilding ? 1 : 0)

        let size = MemoryLayout<OsmConstants>.size

        osmConstantsBufferOffset += size
        if osmConstantsBufferOffset >= osmConstantsBufferLength {
            osmConstantsBufferOffset = 0
        }

        let pointer = osmConstantsBuffer.contents().advanced(by: osmConstantsBufferOffset)

        pointer.copyMemory(from: &constants, byteCount: size)
    }
}

// MARK: - MTKViewDelegate

extension Renderer: MTKViewDelegate {

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {

    }

    func draw(in view: MTKView) {
        frameSemaphore.wait()

        updateFrameConstants()

        guard let drawable = mtkView.currentDrawable else {
            return
        }

        guard let renderPassDescriptor = view.currentRenderPassDescriptor else {
            return
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        encoder.setRenderPipelineState(renderPipelineState)
        encoder.setDepthStencilState(depthStencilState)

        encoder.setVertexBuffer(constantsBuffer, offset: constantsBufferOffset, index: 1)

        encoder.setVertexBuffer(nodesBuffer, offset: 0, index: 0)
//        encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: nodeCoords.count)

        // MARK: Draw ways

        updateOsmConstants(isBuilding: false)
        encoder.setVertexBuffer(osmConstantsBuffer, offset: osmConstantsBufferOffset, index: 2)
        encoder.setFragmentBuffer(osmConstantsBuffer, offset: osmConstantsBufferOffset, index: 0)

        for wayNodeIndexBuffer in wayNodeIndexBuffers {
            encoder.drawIndexedPrimitives(type: .lineStrip,
                                          indexCount: wayNodeIndexBuffer.indexCount,
                                          indexType: .uint16,
                                          indexBuffer: wayNodeIndexBuffer.buffer,
                                          indexBufferOffset: 0)
        }

        // MARK: Draw buildings

        updateOsmConstants(isBuilding: true)
        encoder.setVertexBuffer(osmConstantsBuffer, offset: osmConstantsBufferOffset, index: 2)
        encoder.setFragmentBuffer(osmConstantsBuffer, offset: osmConstantsBufferOffset, index: 0)

        for buildingNodeIndexBuffer in buildingNodeIndexBuffers {
            encoder.drawIndexedPrimitives(type: .lineStrip,
                                          indexCount: buildingNodeIndexBuffer.indexCount,
                                          indexType: .uint16,
                                          indexBuffer: buildingNodeIndexBuffer.buffer,
                                          indexBufferOffset: 0)
        }

        encoder.endEncoding()

        commandBuffer.present(drawable)

        commandBuffer.addCompletedHandler { [weak self] _ in
            self?.frameSemaphore.signal()
        }

        commandBuffer.commit()

        frameIndex += 1
    }
}
