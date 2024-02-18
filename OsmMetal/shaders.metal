//
//  shaders.metal
//  OsmMetal
//
//  Created by Roope on 7.3.2024.
//

#include <metal_stdlib>
using namespace metal;

struct FrameConstants {
    float4x4 view;
    float4x4 projection;
};

struct OsmConstants {
    bool isBuilding;
};

struct VertexIn {
    float2 lonlat [[attribute(0)]];
};

struct VertexOut {
    float4 position [[position]];
    float pointSize [[point_size]];
};

vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                             constant FrameConstants &frame [[buffer(1)]],
                             constant OsmConstants &osm [[buffer(2)]])
{
    VertexOut out;
    out.position = frame.projection * frame.view * float4(in.lonlat.x, 0.0, in.lonlat.y, 1.0);
    out.pointSize = 4.0;
    if (osm.isBuilding) {
        out.position.y += 0.01;
    }
    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]],
                              constant OsmConstants &osm [[buffer(0)]])
{
    if (osm.isBuilding) {
        return float4(0.0, 0.5, 1.0, 1.0);
    } else {
        return float4(1.0, 1.0, 1.0, 1.0);
    }
}
