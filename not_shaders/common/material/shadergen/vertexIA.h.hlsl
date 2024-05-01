#ifndef VERTEX_AI_UTIL_H_HLSL
#define VERTEX_AI_UTIL_H_HLSL

// Vertex Shader Input
struct VertexIa {
    float3 pos;
    float3 normal;
    float4 tangent;
    float4 texCoords;
    float4 color;
    half visibility;
};


// Vertex input permutations

struct VertexIaMeshExtra {

    float3 pos : POSITION;
    float tangentW : TEXCOORD3;
    float3 normal : NORMAL;
    float3 tangent : TANGENT;
    float2 texCoord0 : TEXCOORD0;
    float2 texCoord1 : TEXCOORD1;
    float4 color : COLOR;
    float texCoord2 : TEXCOORD2;
};

struct VertexIaMesh {
    float3 pos : POSITION;
    float tangentW : TEXCOORD3;
    float3 normal : NORMAL;
    float3 tangent : TANGENT;
    float2 texCoord0 : TEXCOORD0;
};

struct VertexIaDecal {
   float3 pos              : POSITION;
   float3 normal           : NORMAL;
   float3 tangent          : TANGENT;
   float2 texCoord         : TEXCOORD0;
   float tangentW          : TEXCOORD1;
   float4 tcStartEndFading : TEXCOORD2;
};

struct VertexIaDecalRoad {
   float3 pos              : POSITION;
   float visibility        : TEXCOORD0;
   float2 texCoord         : TEXCOORD1;
   float normalPacked       : NORMAL;
   float tangentPacked      : TANGENT;
};

struct VertexIaPNTBT {
   float3 pos       : POSITION;
   float3 normal    : NORMAL;
   float3 tangent   : TANGENT;
   float3 B         : BINORMAL;
   float2 texCoord  : TEXCOORD0;
};

struct VertexIaPNTT {
   float3 pos       : POSITION;
   float3 normal    : NORMAL;
   float3 tangent   : TANGENT;
   float2 texCoord  : TEXCOORD0;
};


struct VertexIaPCT {
   float3 pos       : POSITION;
   float4 color     : COLOR;
   float2 texCoord  : TEXCOORD0;
};

struct VertexIaBB {
   float tcImposterCorner       : TEXCOORD4;
   float4 position              : POSITION;
   float2 tcImposterParams      : TEXCOORD0;
   float3 tcImposterUpVec       : TEXCOORD1;
   float3 tcImposterRightVec    : TEXCOORD2;
};

struct VertexIaP {
   float3 pos : POSITION;
};

struct VertexIaEmpty {

};


#if defined(GFXVERTEXFORMAT_MESHEXTRA)
    #define vertexIARAW VertexIaMeshExtra
    VertexIa getVertexIA(vertexIARAW vtxRaw) {
        VertexIa vtx;
        vtx.pos = vtxRaw.pos;
        vtx.normal = vtxRaw.normal;
        vtx.tangent = float4(vtxRaw.tangent, vtxRaw.tangentW);
        vtx.texCoords = float4(vtxRaw.texCoord0, vtxRaw.texCoord1);
        vtx.color = vtxRaw.color;
        vtx.visibility = 1;
        return vtx;
    }
#elif defined(GFXVERTEXFORMAT_MESH)
    #define vertexIARAW VertexIaMesh
    VertexIa getVertexIA(vertexIARAW vtxRaw) {
        VertexIa vtx;
        vtx.pos = vtxRaw.pos;
        vtx.normal = vtxRaw.normal;
        vtx.tangent = float4(vtxRaw.tangent, vtxRaw.tangentW);
        vtx.texCoords = vtxRaw.texCoord0.xyxy;
        vtx.color = 1;
        vtx.visibility = 1;
        return vtx;
    }
#elif defined(GFXVERTEXFORMAT_P)
    #define vertexIARAW VertexIaP
    VertexIa getVertexIA(vertexIARAW vtxRaw) {
        VertexIa vtx;
        vtx.pos = vtxRaw.pos;
        vtx.normal = normalize(-vEye); // normal pointing the camera ???
        vtx.texCoords = 0;
        vtx.tangent = 0;
        vtx.color = 1;
        vtx.visibility = 1;
        return vtx;
    }
#elif defined(GFXVERTEXFORMAT_DECAL)
    #define vertexIARAW VertexIaDecal
    VertexIa getVertexIA(vertexIARAW vtxRaw) {
        VertexIa vtx;
        vtx.pos = vtxRaw.pos;
        vtx.normal = vtxRaw.normal;
        vtx.tangent = float4(vtxRaw.tangent, vtxRaw.tangentW);
        vtx.texCoords = vtxRaw.texCoord.xyxy;
        vtx.color = 1;
        vtx.visibility = 1;
        return vtx;
    }
#elif defined(GFXVERTEXFORMAT_DECALROAD)
    #define vertexIARAW VertexIaDecalRoad
    VertexIa getVertexIA(vertexIARAW vtxRaw) {
        VertexIa vtx;
        vtx.pos = vtxRaw.pos;
        vtx.normal = normalize(unpackColor(asuint(vtxRaw.normalPacked)).xyz * 2 - 1);
        vtx.tangent = float4(normalize(unpackColor(asuint(vtxRaw.tangentPacked)).xyz * 2 - 1), 1);
        vtx.texCoords = vtxRaw.texCoord.xyxy;
        vtx.color = 1;
        vtx.visibility = (half)vtxRaw.visibility;
        return vtx;
    }
#elif defined(GFXVERTEXFORMAT_PNTTB)
    #define vertexIARAW VertexIaMesh
    VertexIa getVertexIA(vertexIARAW vtxRaw) {
        VertexIa vtx;
        vtx.pos = vtxRaw.pos;
        vtx.normal = vtxRaw.normal;
        vtx.tangent = float4(vtxRaw.tangent, vtxRaw.tangentW);
        vtx.texCoords = 0;
        vtx.color = 1;
        vtx.visibility = 1;
        return vtx;
    }
#elif defined(GFXVERTEXFORMAT_PNTBT)
    #define vertexIARAW VertexIaPNTBT
    VertexIa getVertexIA(vertexIARAW vtxRaw) {
        VertexIa vtx;
        vtx.pos = vtxRaw.pos;
        vtx.normal = vtxRaw.normal;
        vtx.tangent = float4(vtxRaw.tangent, 1);
        vtx.texCoords = vtxRaw.texCoord.xyxy;
        vtx.color = 1;
        vtx.visibility = 1;
        return vtx;
    }
#elif defined(GFXVERTEXFORMAT_PNTT)
    #define vertexIARAW VertexIaPNTT
    VertexIa getVertexIA(vertexIARAW vtxRaw) {
        VertexIa vtx;
        vtx.pos = vtxRaw.pos;
        vtx.normal = vtxRaw.normal;
        vtx.tangent = float4(vtxRaw.tangent, 1);
        vtx.texCoords = vtxRaw.texCoord.xyxy;
        vtx.color = 1;
        vtx.visibility = 1;
        return vtx;
    }
#elif defined(GFXVERTEXFORMAT_PCT)
    #define vertexIARAW VertexIaPCT
    VertexIa getVertexIA(vertexIARAW vtxRaw) {
        VertexIa vtx;
        vtx.pos = vtxRaw.pos;
        vtx.normal = normalize(-vEye); // normal pointing the camera ???
        vtx.tangent = float4(float3(0, 0, 1), 1); // TODO
        vtx.texCoords = vtxRaw.texCoord.xyxy;
        vtx.color = vtxRaw.color;
        vtx.visibility = 1;
        return vtx;
    }
#elif defined(GFXVERTEXFORMAT_IMPOSTER_BB)
    #include "shaders/common/imposter.hlsl"
    #define vertexIARAW VertexIaBB
    VertexIa getVertexIA(vertexIARAW vtxRaw) {
        VertexIa vtx;
        float3x3 worldToTangent;
        const float4 imposterLimits = materialUniforms.imposterLimits;
        imposter_v( vtxRaw.position.xyz, vtxRaw.tcImposterCorner, vtxRaw.tcImposterParams.x * length(vtxRaw.tcImposterRightVec), normalize(vtxRaw.tcImposterUpVec),
            normalize(vtxRaw.tcImposterRightVec), imposterLimits.y, imposterLimits.x, imposterLimits.z, imposterLimits.w, eyePosWorld, materialUniforms.imposterUVs, vtx.pos, vtx.texCoords.xy, worldToTangent );

        vtx.normal = worldToTangent[2];
        vtx.tangent = float4(worldToTangent[0], -1);
        vtx.texCoords = vtx.texCoords.xyxy;
        vtx.color = 1;
        vtx.visibility = (half)vtxRaw.tcImposterParams.y;
        return vtx;
    }
#else
    #define vertexIARAW VertexIaEmpty
    VertexIa getVertexIA(vertexIARAW vtxRaw) {
        VertexIa vtx = (VertexIa)0;
        vtx.color = 1;
        vtx.visibility = 1;
        return vtx;
    }
#endif

#endif //VERTEX_AI_UTIL_H_HLSL
