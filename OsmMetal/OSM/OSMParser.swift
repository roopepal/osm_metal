//
//  OSMParser.swift
//  OsmMetal
//
//  Created by Roope on 26.2.2024.
//

import Foundation

class OSMParser: NSObject, XMLParserDelegate {

    var osm: Osm!

    var lastWay: Osm.Way!

    var nodeCount = 0

    var currentTaggable: Taggable?

    func parser(
        _ parser: XMLParser,
        didStartElement elem: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attr: [String: String] = [:]
    ) {
        switch elem {

        case "osm":
            osm = Osm()

        case "bounds":
            osm.bounds = Osm.Bounds(
                minlat: Double(attr["minlat"]!)!,
                minlon: Double(attr["minlon"]!)!,
                maxlat: Double(attr["maxlat"]!)!,
                maxlon: Double(attr["maxlon"]!)!)

        case "node":
            let node = Osm.Node(
                id: Int(attr["id"]!)!,
                lat: Double(attr["lat"]!)!,
                lon: Double(attr["lon"]!)!,
                index: nodeCount)
            osm.nodes.append(node)
            nodeCount += 1
            currentTaggable = node

        case "way":
            let way = Osm.Way(id: Int(attr["id"]!)!)
            osm.ways.append(way)
            lastWay = way
            currentTaggable = way

        case "nd":
            let nd = Osm.Way.Nd(ref: Int(attr["ref"]!)!)
            lastWay.nds.append(nd)

        case "tag":
            if let key = attr["k"], let value = attr["v"] {
                currentTaggable?.tags[key] = value
            }

        default:
            return
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if ["node", "way"].contains(elementName) {
            currentTaggable = nil
        }
    }
}
