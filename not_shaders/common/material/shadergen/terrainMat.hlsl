#define SHADERGEN_CUSTOM_MATERIAL_CBUFFER 1
#include "shadergen.h.hlsl"
#include "shaders/common/terrain/terrain.hlsl"

uniform Texture2D heightMap       : REGISTER(t9, space1);
uniform Texture2D terrainEmptyMap : REGISTER(t10, space1);
uniform Texture2D baseTexMap      : REGISTER(t11, space1);
uniform Texture2D layerTex        : REGISTER(t12, space1);
uniform StructuredBuffer<TerrainMaterial>  terrainMaterialDataT : REGISTER(t13, space1);
uniform Texture2DArray<float4> baseColorBaseTex : REGISTER(t14, space1);
uniform Texture2DArray<float4> baseColorMacroTex : REGISTER(t15, space1);
uniform Texture2DArray<float4> baseColorDetailTex : REGISTER(t16, space1);
uniform Texture2DArray<float4> normalBaseTex   : REGISTER(t17, space1);
uniform Texture2DArray<float4> normalMacroTex  : REGISTER(t18, space1);
uniform Texture2DArray<float4> normalDetailTex : REGISTER(t19, space1);

cbuffer cspMaterial : REGISTER(b4, space1) {
    float oneOverTerrainSize;
    float squareSize;
    float layerSize;
    int terrainFlags;
}

// TODO

struct MaterialLayer {
    half3 baseColor;
    half opacity;
    half3 normal;
    half metallic;
    half3 emissive;
    half roughness;
    half ao;
    half clearCoat;
    half clearCoatRoughness;
    half3 annotationColor;
};

struct VtxOut {
    float4 svPos : SV_POSITION;
    float4 posSS : POSITION0; // this is in clip space
    float3 posWs : TEXCOORD0;
    float3 normalWs : NORMAL;
    float4 tangentWs : TANGENT;
    float4 terrainUv_texCoords : TEXCOORD1;
    uint instanceId : TEXCOORD2;
    float dist : TEXCOORD3;

    #ifdef MFT_ClipPlane0
        float ClipDistance0   : SV_ClipDistance0;
    #endif
};

#define TerrainDetailLod TerrainDetailNormal
#define TerrainFlags_usePerPixelHeightNormal (1 << 0)

MaterialLayer processLayers(VtxOut vtx) {
    MaterialLayer outLayer = (MaterialLayer)0;
    outLayer.opacity = 1;

    #if defined(MFT_TerrainVertEmpty)
        clip((1.0f - terrainEmptyMap.Load( int3(vtx.terrainUv_texCoords.xy * terrainHeightMapSize - 0.5f, 0) ).r) - 0.0001f);
    #endif


    const float4 layerSample = round( layerTex.Sample(defaultSamplerRT, vtx.terrainUv_texCoords.zw ) * 255.0f );
    TerrainMaterialOutput terrainProp = blendTerrainMaterials(vtx.terrainUv_texCoords.zw, layerSize,  layerSample, vtx.dist, TerrainDetailLod);
    outLayer.metallic = 0;
    outLayer.baseColor = (half3)terrainProp.baseColor;
    outLayer.roughness = (half)terrainProp.roughness;
    outLayer.ao = (half)terrainProp.ao;
    outLayer.annotationColor = (half3)terrainProp.annotation;
    if(terrainFlags & TerrainFlags_usePerPixelHeightNormal) {
        const float3 heightNormal = getNormalFromHeightmap(heightMap, vtx.terrainUv_texCoords.xy, 1.0f / terrainHeightMapSize, terrainHeightAspect);
        const float3 heightTang = normalize(cross(float3(0, 1, 0), heightNormal));
        outLayer.normal = (half3)mul(getTangentToWorldNormalMatrix(heightNormal, float4(heightTang, 1)), terrainProp.normal);
    }
    else {
        outLayer.normal = (half3)terrainProp.normal;
    }
    return outLayer;
}

VertexIa processVtx(VertexIa inVtx, uint instanceIdx, float4x4 objTrans, uint terrailDetail) {
    inVtx.pos = calculateTerrainVertexPos(inVtx.pos, heightMap, terrainEmptyMap, inVtx.normal, inVtx.texCoords.xy);
    if(terrainFlags & TerrainFlags_usePerPixelHeightNormal) inVtx.normal = float3(0, 0, 1);
    return inVtx;
}

VtxOut mainV(vertexIARAW inVtxRaw, svInstanceData instanceData) {
    VtxOut vtxOut;
    vtxOut.instanceId = getInstanceId(instanceData);
    const float4x4 instanceTransform = getInstanceTransform(vtxOut.instanceId);
    const VertexIa vtxIn = processVtx(getVertexIA(inVtxRaw), vtxOut.instanceId, instanceTransform, TerrainDetailLod);

    vtxOut.terrainUv_texCoords.xy = vtxIn.texCoords.xy;
    vtxOut.terrainUv_texCoords.zw = (vtxIn.pos.xy * oneOverTerrainSize.xx);
    float3 N = normalize(vtxIn.normal);
    vtxOut.normalWs = normalize(mul((float3x3)instanceTransform, mul((float3x3)localTrans, N)));
    const float3 T = normalize( cross(float3( 0, 1, 0 ), N) );
    vtxOut.tangentWs.xyz = normalize(mul((float3x3)instanceTransform, mul((float3x3)localTrans, T)));
    vtxOut.tangentWs.xyz = T;
    vtxOut.tangentWs.w = 1;
    vtxOut.posWs = mul(instanceTransform, mul(localTrans, float4(vtxIn.pos, 1))).xyz;
    vtxOut.dist = length(eyePosWorld - vtxOut.posWs);
    const float4x4 localToCameraM = mul(worldToCameraPos0, subMatrixPosition(instanceTransform, eyePosWorld));
    vtxOut.svPos = mul(cameraToScreen, mul(localToCameraM, mul(localTrans, float4(vtxIn.pos, 1))));

    #ifdef MFT_ParaboloidVertTransform
        paraboloidVert(vtxOut.svPos, vtxOut.paraboloidPos);
    #endif

    #ifdef MFT_ClipPlane0
        vtxOut.ClipDistance0 = dot(float4(vtxOut.posWs, 1), clipPlane0);
    #endif

    vtxOut.posSS = vtxOut.svPos;
    return vtxOut;
}

Fragout mainP(VtxOut vtx, bool isFrontFacing : SV_IsFrontFace) {
    #ifdef MFT_ParaboloidVertTransform
        clip( abs( vtx.paraboloidPos.z ) - 0.999 );
        clip( 1.0 - abs(vtx.paraboloidPos.x) );
    #endif

    const MaterialLayer layer = processLayers(vtx);

    vtx.normalWs = normalize(vtx.normalWs);
    vtx.tangentWs.xyz = normalize(vtx.tangentWs.xyz);

    Material material = (Material)0;
    material.baseColor = layer.baseColor;
    material.metallic = layer.metallic;
    material.roughness = layer.roughness;
    material.opacity = layer.opacity;
    material.ambientOclussion = layer.ao;
    material.emissive = layer.emissive;
    material.clearCoat = layer.clearCoat;
    material.clearCoatRoughness = layer.clearCoatRoughness;
    material.normalsWS = mul(getTangentToWorldNormalMatrix(vtx.normalWs, vtx.tangentWs), layer.normal);
    material.clearCoat2ndNormalWS = material.normalsWS;

    material.diffColor = saturate((1 - material.metallic) * material.baseColor);
    material.specColor = max(0.001, saturate(lerp(0.04, material.baseColor, material.metallic)));

    material.geomNormalWS = vtx.normalWs;
    material.positionWS = vtx.posWs;
    material.positionLastWS = vtx.posWs;
    material.texCoords = vtx.terrainUv_texCoords.zwzw;
    material.positionSS = vtx.posSS;
    material.vpos = vtx.svPos;
    material.instanceId = vtx.instanceId;
    material.visibility = 1;
    material.lightIds = getInstanceLightIds(vtx.instanceId);;
    material.layerCount = 4;
    material.annotationColor = half4(layer.annotationColor, 1);

    return processMaterial(material);
}

#include "shaders/common/terrain/terrainImpl.hlsl"
