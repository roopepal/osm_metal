//
//  ViewController.swift
//  OsmMetal
//
//  Created by Roope on 18.2.2024.
//

import Cocoa
import Metal
import MetalKit

class ViewController: NSViewController {

    var osm: Osm!

    var renderer: Renderer!

    @IBOutlet weak var mtkView: MTKView!

    @IBAction func rotationChanged(_ sender: NSSlider) {
        renderer.rotation = sender.floatValue
    }

    @IBAction func zoomChanged(_ sender: NSSlider) {
        renderer.zoom = sender.floatValue
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let data = try? Data(
            contentsOf: Bundle.main.url(
                forResource: "esplanadinpuisto",
                withExtension: "osm")!
        ) else {
            fatalError()
        }

        let osmParser = OSMParser()

        let parser = XMLParser(data: data)
        parser.delegate = osmParser
        parser.parse()

        osm = osmParser.osm

        let actualBounds = osm.actualBounds

        print(actualBounds)

        print("Parser done")

        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError()
        }

        renderer = Renderer(device: device,
                            view: mtkView,
                            nodes: osm.nodes,
                            bounds: osm.bounds,
                            ways: osm.ways)
    }
}
