#define SHADERGEN_CUSTOM_MATERIAL_CBUFFER 1
#define CUSTOM_MATERIAL_BLOCK float cubemapReflectivity;

#include "../shadergen.h.hlsl"
#include "shaders/common/terrain/terrain.hlsl"

uniform Texture2D heightMap       : REGISTER(t9, space1);
uniform Texture2D terrainEmptyMap : REGISTER(t10, space1);
uniform Texture2D baseTexMap      : REGISTER(t11, space1);
uniform Texture2D layerTex        : REGISTER(t12, space1);

#define MATERIAL_V0_TEXTURE_DETAIL_IDX 0
#define MATERIAL_V0_TEXTURE_MACRO_IDX 1
#define MATERIAL_V0_TEXTURE_NORMAL_IDX 2
#define MATERIAL_V0_TEXTURES_PER_LAYER 3
#define MATERIAL_V0_TEXTURES_MAX 100
uniform Texture2D<float4> terrainTex[MATERIAL_V0_TEXTURES_MAX] : REGISTER(t13, space1);

uint getMaterialTexIdx(uint layer, uint textureType) {
    const uint arrayTex[] = TEXTURE_IDX_ARRAY;
    return arrayTex[((MATERIAL_V0_TEXTURES_PER_LAYER * layer) + textureType)];
}

Texture2D getMaterialTex(uint layer, uint textureType) {
    return terrainTex[getMaterialTexIdx(layer, textureType)];
}

struct LayerUniforms {
    float4 detailScaleAndFade;
    float4 macroScaleAndFade;
    float3 detailIdStrengthParallax;
    uint flags;
    float3 macroIdStrengthParallax;
    float padding1;
};

cbuffer cspMaterial : REGISTER(b4, space1) {
    float oneOverTerrainSize;
    float squareSize;
    float uTerrainLayerSize;
    float padding;
    LayerUniforms uLayers[32];
}

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

struct TerrainLayer {
    float blendTotal;
    float4 annotationColorBlend;
    float3 diffColor;
    float3 normal;
};

void processTerrainLayer(VtxOut vtx, inout TerrainLayer layer, uint layerIdx, float4 baseColor, float4 layerSample) {
    if(!(terrainMaterials & (uint(1) << layerIdx))) {
        return;
    }

    const float3 inTexCoord = vtx.terrainUv_texCoords.zwz;
    const float3 annotationColor0 = float3(0, 1, 0);

    // Terrain Detail Texture
    {
        float detailBlend = 0;
        float4 detCoord = 0;
        detCoord = float4(inTexCoord.xyz * uLayers[layerIdx].detailScaleAndFade.xyx, 0);
        detCoord.w = clamp( ( uLayers[layerIdx].detailScaleAndFade.z - vtx.dist ) * uLayers[layerIdx].detailScaleAndFade.w, 0.0, 1.0 );
        detailBlend = calcBlend( uLayers[layerIdx].detailIdStrengthParallax.x, inTexCoord.xy, uTerrainLayerSize, layerSample );
        if ( getMaterialTexIdx(layerIdx, MATERIAL_V0_TEXTURE_DETAIL_IDX) && detailBlend > 0.0f ) {
            layer.blendTotal = max( layer.blendTotal, detailBlend );
            half3 detailColor = (half3)getMaterialTex(layerIdx, MATERIAL_V0_TEXTURE_DETAIL_IDX).Sample(defaultSampler2D, detCoord.xy ).xyz * 2.0 - 1.0;
            detailColor *= (half3)(uLayers[layerIdx].detailIdStrengthParallax.y * detCoord.w);
            layer.diffColor = lerp( layer.diffColor, baseColor.rgb + detailColor, detailBlend );

            if(detailBlend >= 0.5) {
                layer.annotationColorBlend = float4(annotationColor0, detailBlend); // TODO
            }
        }

        // Terrain Normal Texture
        detailBlend = min( detailBlend, detCoord.w );
        if( getMaterialTexIdx(layerIdx, MATERIAL_V0_TEXTURE_NORMAL_IDX) && detailBlend > 0.0f ){
            const half4 bumpNormal0 = (half4)getMaterialTex(layerIdx, MATERIAL_V0_TEXTURE_NORMAL_IDX).Sample(defaultSampler2D, detCoord.xy);
            layer.normal = lerp(layer.normal, decodeNormal(bumpNormal0, uLayers[layerIdx].flags), detailBlend);
        }
    }

    // Terrain Macro Texture
    {
        const float macroBlend = calcBlend( uLayers[layerIdx].macroIdStrengthParallax.x, inTexCoord.xy, uTerrainLayerSize, layerSample );
        if ( getMaterialTexIdx(layerIdx, MATERIAL_V0_TEXTURE_MACRO_IDX) && macroBlend > 0.0f ) {
            layer.blendTotal = max( layer.blendTotal, macroBlend );
            float4 macroCoord = float4(inTexCoord.xyz * uLayers[layerIdx].macroScaleAndFade.xyx, 0);
            macroCoord.w = clamp( ( uLayers[layerIdx].macroScaleAndFade.z - vtx.dist ) * uLayers[layerIdx].macroScaleAndFade.w, 0.0, 1.0 );
            half3 macroColor = (half3)getMaterialTex(layerIdx, MATERIAL_V0_TEXTURE_MACRO_IDX).Sample(defaultSampler2D, macroCoord.xy ).xyz * 2.0 - 1.0;
            macroColor *= (half3)(uLayers[layerIdx].macroIdStrengthParallax.y * macroCoord.w);
            layer.diffColor = lerp( layer.diffColor, layer.diffColor + macroColor, macroBlend );

            if(macroBlend >= 0.5) {
                layer.annotationColorBlend = float4(annotationColor0, macroBlend);
            }
        }
    }
}

TerrainLayer processLayers(VtxOut vtx) {
    #if defined(MFT_TerrainVertEmpty)
        clip((1.0f - terrainEmptyMap.Load( int3(vtx.terrainUv_texCoords.xy * terrainHeightMapSize - 0.5f, 0) ).r) - 0.0001f);
    #endif
    // TODO we use this normal?
    float3 layerNormal = getNormalFromHeightmap(heightMap, vtx.terrainUv_texCoords.xy, 1.0f / terrainHeightMapSize, terrainHeightAspect);

    const half4 baseColor = (half4)baseTexMap.Sample(defaultSampler2D, vtx.terrainUv_texCoords.zw);
    const float4 layerSample = round( layerTex.Sample(defaultSamplerRT, vtx.terrainUv_texCoords.zw ) * 255.0f );
    TerrainLayer layer = (TerrainLayer)0;
	layer.diffColor = baseColor.rgb;
    layer.normal = float3(0, 0, 1);
    const uint layerCount = 32; // TODO uniform?
    for(uint i = 0; i < layerCount; ++i) {
        processTerrainLayer(vtx, layer, i, baseColor, layerSample);
    }
    layer.diffColor = toLinearColor(layer.diffColor);

    return layer;
}

VertexIa processVtx(VertexIa inVtx, uint instanceIdx, float4x4 objTrans) {
    inVtx.pos = calculateTerrainVertexPos(inVtx.pos, heightMap, terrainEmptyMap, inVtx.normal, inVtx.texCoords.xy);
    return inVtx;
}

VtxOut mainV(vertexIARAW inVtxRaw, svInstanceData instanceData) {
    VtxOut vtxOut;
    vtxOut.instanceId = getInstanceId(instanceData);
    const float4x4 instanceTransform = getInstanceTransform(vtxOut.instanceId);
    const VertexIa vtxIn = processVtx(getVertexIA(inVtxRaw), vtxOut.instanceId, instanceTransform);

    vtxOut.terrainUv_texCoords.xy = vtxIn.texCoords.xy;
    vtxOut.terrainUv_texCoords.zw = (vtxIn.pos.xy * oneOverTerrainSize.xx);
    const float3 N = normalize(vtxIn.normal);
    vtxOut.normalWs = normalize(mul((float3x3)instanceTransform, mul((float3x3)localTrans, N)));
    const float3 T = normalize( cross(float3( 0, 1, 0 ),  N) );
    vtxOut.tangentWs.xyz = normalize(mul((float3x3)instanceTransform, mul((float3x3)localTrans, T)));
    vtxOut.tangentWs.w = 1;
    vtxOut.posWs = mul(instanceTransform, mul(localTrans, float4(vtxIn.pos, 1))).xyz;
    vtxOut.dist = length(eyePosWorld - vtxOut.posWs);
    const float4x4 localToCameraM = mul(worldToCameraPos0, subMatrixPosition(instanceTransform, eyePosWorld));
    vtxOut.svPos = mul(cameraToScreen, mul(localToCameraM, mul(localTrans, float4(vtxIn.pos, 1))));

    #ifdef MFT_ParaboloidVertTransform___ // TODO
        paraboloidVert(vtxOut.svPos, vtxOut.paraboloidPos);
    #endif

    #ifdef MFT_ClipPlane0
        vtxOut.ClipDistance0 = dot(float4(vtxOut.posWs, 1), clipPlane0);
    #endif

    vtxOut.posSS = vtxOut.svPos;
    return vtxOut;
}

Fragout mainP(VtxOut vtx, bool isFrontFacing : SV_IsFrontFace) {
    #ifdef MFT_ParaboloidVertTransform___ // TODO
        clip( abs( vtx.paraboloidPos.z ) - 0.999 );
        clip( 1.0 - abs(vtx.paraboloidPos.x) );
    #endif
    vtx.normalWs = normalize(vtx.normalWs);

    const TerrainLayer terLayer = processLayers(vtx);
    Material material = (Material)0;
    material.baseColor = terLayer.diffColor;
    material.metallic = 0;
    material.roughness = 1;
    material.opacity = 1;
    material.ambientOclussion = 1;
    material.normalsWS = mul(getTangentToWorldNormalMatrix(vtx.normalWs, vtx.tangentWs), terLayer.normal);
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

    return processMaterial(material);
}

//#include "shaders/common/terrain/terrainImpl.hlsl"
