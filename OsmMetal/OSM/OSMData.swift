//
//  OSMData.swift
//  OsmMetal
//
//  Created by Roope on 18.2.2024.
//

import Foundation

protocol Taggable {
    var tags: [String: String] { get set }
}

class Osm {
    var bounds: Bounds!

    struct Bounds {
        var minlat: Double
        var minlon: Double
        var maxlat: Double
        var maxlon: Double
    }

    var nodes: [Node] = []

    class Node: Taggable {
        init(id: Int, lat: Double, lon: Double, index: Int) {
            self.id = id
            self.lat = lat
            self.lon = lon
            self.index = index
        }

        var id: Int
        var lat: Double
        var lon: Double
        var tags: [String: String] = [:]

        /// For indexed drawing
        var index: Int
    }

    var ways: [Way] = []

    class Way: Taggable {
        init(id: Int) {
            self.id = id
        }

        var id: Int
        var nds: [Nd] = []
        var tags: [String: String] = [:]

        // swiftlint:disable:next nesting type_name
        struct Nd {
            var ref: Int
        }
    }
}

extension Osm {

    var actualBounds: Bounds {
        guard let first = nodes.first else {
            fatalError()
        }

        var minLatNode: Node = first
        var minLonNode: Node = first
        var maxLatNode: Node = first
        var maxLonNode: Node = first

        for node in nodes.dropFirst() {
            if !nodeHasAtLeastOneRef(node: node) { continue }
            if node.lat < minLatNode.lat { minLatNode = node }
            if node.lon < minLonNode.lon { minLonNode = node }
            if node.lat > maxLatNode.lat { maxLatNode = node }
            if node.lon > maxLonNode.lon { maxLonNode = node }
        }

        print("minLatNode \(minLatNode.id)")
        print("minLonNode \(minLonNode.id)")
        print("maxLatNode \(maxLatNode.id)")
        print("maxLonNode \(maxLonNode.id)")

        return Bounds(minlat: minLatNode.lat,
                      minlon: minLonNode.lon,
                      maxlat: maxLatNode.lat,
                      maxlon: maxLonNode.lon)
    }

    func nodeHasAtLeastOneRef(node: Node) -> Bool {
        for way in ways {
            for nd in way.nds where nd.ref == node.id {
                return true
            }
        }
        return false
    }
}

extension Osm.Bounds {

    /// longitude : latitude
    var aspectRatio: Double {
        return (maxlon - minlon) / (maxlat - minlat)
    }
}

extension Osm.Way {

    var isBuilding: Bool {
        tags.contains { $0.key.contains("building") && $0.value == "yes" }
    }
}
