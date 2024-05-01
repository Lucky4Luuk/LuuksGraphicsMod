#include "shadergen.h.hlsl"
#ifdef MFT_WindEffect
#include "shaders/common/wind.hlsl"
#endif
#ifdef MFT_Foliage
#include "shaders/common/foliage.hlsl"
#endif
#include "shaders/common/vehicle/vehiclePartData.h.hlsl"
// #include "customLightingModel.hlsl"

#define MATERIAL_TEXTURE_OPACITY_IDX 0
#define MATERIAL_TEXTURE_NORMAL_IDX 1
#define MATERIAL_TEXTURE_BASECOLOR_IDX 2
#define MATERIAL_TEXTURE_METALLIC_IDX 3
#define MATERIAL_TEXTURE_ROUGHNESS_IDX 4
#define MATERIAL_TEXTURE_AO_IDX 5
#define MATERIAL_TEXTURE_EMISSIVE_IDX 6
#define MATERIAL_TEXTURE_BASECOLOR_DETAIL_IDX 7
#define MATERIAL_TEXTURE_NORMAL_DETAIL_IDX 8
#define MATERIAL_TEXTURE_PALETTE_IDX 9
#define MATERIAL_TEXTURE_CLEARCOAT_IDX 10
#define MATERIAL_TEXTURE_CLEARCOAT_ROUGHNESS_IDX 11
#define MATERIAL_TEXTURES_PER_LAYER 12
#define MATERIAL_TEXTURES_MAX 24

TextureCube cubemap : REGISTER(t9, space1);
StructuredBuffer<VehiclePart> flexmeshAlphaBuffer : REGISTER(t10, space1);
StructuredBuffer<VehicleVelocityDataBuffer> vehicleVelocityData : REGISTER(t11, space1);
Texture2D materialTexture[MATERIAL_TEXTURES_MAX] : REGISTER(t12, space1);


TextureCube getCustomCubemap() {
    return cubemap;
}

#if BNG_HLSL_MODEL < 6
uint getMaterialTexIdx(uint layer, uint textureType, uint textureIdx) {
    const uint arrayTex[] = TEXTURE_IDX_ARRAY;
    return arrayTex[((MATERIAL_TEXTURES_PER_LAYER * layer) + textureType)];
}
#else
uint getMaterialTexIdx(uint layer, uint textureType, uint textureIdx) {
    return textureIdx;
}
#endif

Texture2D getMaterialTex(uint index) {
    return materialTexture[index];
}

float2 getTexCoord(uint flags, uint flagIdx, float4 texcoords) {
    return (flags & flagIdx) ? texcoords.zw : texcoords.xy;
}

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
};

struct VtxOut {
    float4 svPos : SV_POSITION;
    float4 posSS : POSITION0; // this is in clip space
    float4 posLastSS : POSITION1;
    float3 posWsLast : POSITION2;
    float3 posWs : TEXCOORD0;
    float4 color : COLOR0;
    float3 normalWs : NORMAL;
    float4 tangentWs : TANGENT;
    float4 texCoords : TEXCOORD1;
    uint instanceId : TEXCOORD2;
    float visibility : TEXCOORD3;
    float4 paraboloidPos : TEXCOORD4;
    uint meshId : TEXCOORD5;

    #ifdef MFT_ClipPlane0
        float ClipDistance0   : SV_ClipDistance0;
    #endif
};

MaterialLayer processLayers(VtxOut vtx, bool isFrontFacing) {
    MaterialLayer outLayer = (MaterialLayer)0;
    outLayer.opacity = 1;
    [unroll]
    for(uint layerIdx = 0; layerIdx < MFT_MATERIAL_LAYER_COUNT; ++layerIdx) {
        const uint layerFlags = materialLayerUniforms[layerIdx].flags;
        float4 texCoords = vtx.texCoords;
        if(layerFlags & MATERIAL_LAYER_FLAG_texCoordAnim) {
            texCoords.xy = mul(materialLayerUniforms[layerIdx].texureAnimM, float4(texCoords.xy, 1, 1)).xy;
            texCoords.zw = mul(materialLayerUniforms[layerIdx].texureAnimM, float4(texCoords.zw, 1, 1)).xy;
        }

        half opacityMapSample = 1;
        [branch] if(materialLayerUniforms[layerIdx].opacityTexIdx > 0) {
            const uint texIdx = getMaterialTexIdx(layerIdx, MATERIAL_TEXTURE_OPACITY_IDX, materialLayerUniforms[layerIdx].opacityTexIdx);
            opacityMapSample = (half)getMaterialTex(texIdx).Sample(defaultSampler2D, getTexCoord(layerFlags, MATERIAL_LAYER_FLAG_opacityMapUV1, texCoords)).x;
        }
        half4 normalMapSample = 0;
        [branch] if(materialLayerUniforms[layerIdx].normalTexIdx > 0) {
            const uint texIdx = getMaterialTexIdx(layerIdx, MATERIAL_TEXTURE_NORMAL_IDX, materialLayerUniforms[layerIdx].normalTexIdx);
            normalMapSample = (half4)getMaterialTex(texIdx).Sample(defaultSampler2D, getTexCoord(layerFlags, MATERIAL_LAYER_FLAG_normalMapUV1, texCoords));
        }
        half3 baseColorMapSample = 1;
        [branch] if(materialLayerUniforms[layerIdx].baseColorTexIdx > 0) {
            const uint texIdx = getMaterialTexIdx(layerIdx, MATERIAL_TEXTURE_BASECOLOR_IDX, materialLayerUniforms[layerIdx].baseColorTexIdx);
            baseColorMapSample = (half3)getMaterialTex(texIdx).Sample(defaultSampler2D, getTexCoord(layerFlags, MATERIAL_LAYER_FLAG_diffuseMapUV1, texCoords)).rgb;
        }
        half metallicMapSample = 1;
        [branch] if(materialLayerUniforms[layerIdx].metallicTexIdx > 0) {
            const uint texIdx = getMaterialTexIdx(layerIdx, MATERIAL_TEXTURE_METALLIC_IDX, materialLayerUniforms[layerIdx].metallicTexIdx);
            metallicMapSample = (half)getMaterialTex(texIdx).Sample(defaultSampler2D, getTexCoord(layerFlags, MATERIAL_LAYER_FLAG_metallicMapUV1, texCoords)).x;
        }
        half roughnessMapSample = 1;
        [branch] if(materialLayerUniforms[layerIdx].roughnessTexIdx > 0) {
            const uint texIdx = getMaterialTexIdx(layerIdx, MATERIAL_TEXTURE_ROUGHNESS_IDX, materialLayerUniforms[layerIdx].roughnessTexIdx);
            roughnessMapSample = (half)getMaterialTex(texIdx).Sample(defaultSampler2D, getTexCoord(layerFlags, MATERIAL_LAYER_FLAG_roughnessMapUV1, texCoords)).x;
        }
        half aoMapSample = 1;
        [branch] if(materialLayerUniforms[layerIdx].aoTexIdx > 0) {
            const uint texIdx = getMaterialTexIdx(layerIdx, MATERIAL_TEXTURE_AO_IDX, materialLayerUniforms[layerIdx].aoTexIdx);
            aoMapSample = (half)getMaterialTex(texIdx).Sample(defaultSampler2D, getTexCoord(layerFlags, MATERIAL_LAYER_FLAG_aoMapUV1, texCoords)).x;
        }
        half3 emissiveMapSample = 1;
        [branch] if(materialLayerUniforms[layerIdx].emissiveTexIdx > 0) {
            const uint texIdx = getMaterialTexIdx(layerIdx, MATERIAL_TEXTURE_EMISSIVE_IDX, materialLayerUniforms[layerIdx].emissiveTexIdx);
            emissiveMapSample = (half3)getMaterialTex(texIdx).Sample(defaultSampler2D, getTexCoord(layerFlags, MATERIAL_LAYER_FLAG_emissiveMapUV1, texCoords)).rgb;
        }
        half4 colorPaletteMapSample = half4(0, 0, 0, 1);
        [branch] if(materialLayerUniforms[layerIdx].colorPaletteTexIdx > 0) {
            const uint texIdx = getMaterialTexIdx(layerIdx, MATERIAL_TEXTURE_PALETTE_IDX, materialLayerUniforms[layerIdx].colorPaletteTexIdx);
            colorPaletteMapSample = (half4)getMaterialTex(texIdx).Sample(defaultSampler2D, getTexCoord(layerFlags, MATERIAL_LAYER_FLAG_colorPaletteMapUV1, texCoords));
        }
        half clearCoatMapSample = 1;
        [branch] if(materialLayerUniforms[layerIdx].clearCoatTexIdx > 0) {
            const uint texIdx = getMaterialTexIdx(layerIdx, MATERIAL_TEXTURE_CLEARCOAT_IDX, materialLayerUniforms[layerIdx].clearCoatTexIdx);
            clearCoatMapSample = (half)getMaterialTex(texIdx).Sample(defaultSampler2D, getTexCoord(layerFlags, MATERIAL_LAYER_FLAG_clearCoatMapUV1, texCoords)).r;
        }
        half clearCoatRoughnessMapSample = 1;
        [branch] if(materialLayerUniforms[layerIdx].clearCoatRoughnessTexIdx > 0) {
            const uint texIdx = getMaterialTexIdx(layerIdx, MATERIAL_TEXTURE_CLEARCOAT_ROUGHNESS_IDX, materialLayerUniforms[layerIdx].clearCoatRoughnessTexIdx);
            clearCoatRoughnessMapSample = (half)getMaterialTex(texIdx).Sample(defaultSampler2D, getTexCoord(layerFlags, MATERIAL_LAYER_FLAG_clearCoatMapUV1, texCoords)).r;
        }

        //detail textures
        half3 baseColorDetailMapSample = 0.5;
        half4 normalDetailMapSample = 0;
        {
            float4 detTexCoords = vtx.texCoords * float4(materialLayerUniforms[layerIdx].detailScale, materialLayerUniforms[layerIdx].detailScale);
            if(layerFlags & MATERIAL_LAYER_FLAG_texCoordAnim) {
                detTexCoords.xy = mul(materialLayerUniforms[layerIdx].texureAnimM, float4(detTexCoords.xy, 1, 1)).xy;
                detTexCoords.zw = mul(materialLayerUniforms[layerIdx].texureAnimM, float4(detTexCoords.zw, 1, 1)).xy;
            }
            [branch] if(materialLayerUniforms[layerIdx].baseColorDetailTexIdx > 0) {
                const uint texIdx = getMaterialTexIdx(layerIdx, MATERIAL_TEXTURE_BASECOLOR_DETAIL_IDX, materialLayerUniforms[layerIdx].baseColorDetailTexIdx);
                baseColorDetailMapSample = (half3)getMaterialTex(texIdx).Sample(defaultSampler2D, getTexCoord(layerFlags, MATERIAL_LAYER_FLAG_detailMapUV1, detTexCoords)).rgb;
            }
            [branch] if(materialLayerUniforms[layerIdx].normalDetailTexIdx > 0) {
                const uint texIdx = getMaterialTexIdx(layerIdx, MATERIAL_TEXTURE_NORMAL_DETAIL_IDX, materialLayerUniforms[layerIdx].normalDetailTexIdx);
                normalDetailMapSample = (half4)getMaterialTex(texIdx).Sample(defaultSampler2D, getTexCoord(layerFlags, MATERIAL_LAYER_FLAG_normalDetailMapUV1, detTexCoords));
            }
        }

        MaterialLayer inLayer;
        inLayer.baseColor = (half3)(materialLayerUniforms[layerIdx].baseColor * ((layerFlags & MATERIAL_LAYER_FLAG_vtxColorToBaseColor) ? vtx.color.xyz : 1));
        inLayer.opacity = (half)materialLayerUniforms[layerIdx].opacity;
        inLayer.metallic = (half)materialLayerUniforms[layerIdx].metallic;
        inLayer.roughness = (half)materialLayerUniforms[layerIdx].roughness;
        inLayer.ao = (half)materialLayerUniforms[layerIdx].ao;
        inLayer.emissive = (half3)materialLayerUniforms[layerIdx].emissive;
        inLayer.clearCoat = (half)materialLayerUniforms[layerIdx].clearCoat;
        inLayer.clearCoatRoughness = (half)materialLayerUniforms[layerIdx].clearCoatRoughness;
        inLayer.normal = half3(0, 0, 1);

        // instance color
        if(materialLayerUniforms[layerIdx].colorPaletteTexIdx <= 0) {
            const half3 instanceColor0 = (half3)unpackColor(getInstanceBaseColors(vtx.instanceId)[0]).rgb;
            inLayer.baseColor *= (layerFlags & MATERIAL_LAYER_FLAG_instanceBaseColor) ? instanceColor0 : 1;
            inLayer.emissive *= (layerFlags & MATERIAL_LAYER_FLAG_instanceEmissive) ? instanceColor0 : 1;
        }
        else {
            #ifdef MFT_FlexMeshVisibility
                const bool useMeshData = unpackColor(flexmeshAlphaBuffer[vtx.meshId].diffColors[0]).a > 0;
            #else
                const bool useMeshData = false;
            #endif
            const uint4 colorsPacked = useMeshData ? (flexmeshAlphaBuffer[vtx.meshId].diffColors) : getInstanceBaseColors(vtx.instanceId);
            const uint4 dataPacked = useMeshData ? uint4(flexmeshAlphaBuffer[vtx.meshId].paintDataPacked, 0) : getInstanceData(vtx.instanceId).instanceCustomData;
            getColorPalette(colorPaletteMapSample, colorsPacked, dataPacked, layerFlags, inLayer.baseColor, inLayer.emissive, inLayer.roughness, inLayer.metallic, inLayer.clearCoat, inLayer.clearCoatRoughness);
        }

        // texture sample merging
        inLayer.opacity *= opacityMapSample;
        inLayer.baseColor *= saturate(baseColorMapSample + (baseColorDetailMapSample * 2 - 1));
        inLayer.metallic *= metallicMapSample;
        inLayer.roughness *= roughnessMapSample;
        inLayer.ao *= aoMapSample;
        inLayer.emissive *= emissiveMapSample;
        inLayer.normal = (materialLayerUniforms[layerIdx].normalTexIdx > 0) ? decodeNormal(normalMapSample, materialLayerUniforms[layerIdx].flags) : inLayer.normal;
        inLayer.normal = normalize(inLayer.normal * half3(materialLayerUniforms[layerIdx].normalMapStrength.xx, 1));
        inLayer.clearCoat *= clearCoatMapSample;
        inLayer.clearCoatRoughness *= clearCoatRoughnessMapSample;
        if(materialLayerUniforms[layerIdx].normalDetailTexIdx > 0) {
            inLayer.normal.xy += half2(decodeNormal(normalDetailMapSample, materialLayerUniforms[layerIdx].flags).xy * materialLayerUniforms[layerIdx].normalDetailMapStrength);
            inLayer.normal = normalize(inLayer.normal);
        }

        // blend layer
        const half layerBlendFactor = (layerIdx == 0) ? 1 : inLayer.opacity;
        outLayer.opacity = lerp(outLayer.opacity, inLayer.opacity, layerBlendFactor);
        outLayer.baseColor = lerp(outLayer.baseColor, inLayer.baseColor, layerBlendFactor);
        outLayer.metallic = lerp(outLayer.metallic, inLayer.metallic, layerBlendFactor);
        outLayer.roughness = lerp(outLayer.roughness, inLayer.roughness, layerBlendFactor);
        outLayer.ao = lerp(outLayer.ao, inLayer.ao, layerBlendFactor);
        outLayer.emissive = lerp(outLayer.emissive, inLayer.emissive, layerBlendFactor);
        outLayer.normal = normalize(lerp(outLayer.normal, inLayer.normal, layerBlendFactor));
        outLayer.clearCoat = lerp(outLayer.clearCoat, inLayer.clearCoat, layerBlendFactor);
        outLayer.clearCoatRoughness = lerp(outLayer.clearCoatRoughness, inLayer.clearCoatRoughness, layerBlendFactor);
    }

    #ifdef MFT_DoubleSided
        outLayer.normal.z *= isFrontFacing ? 1 : -1;
    #endif

    return outLayer;
}

VertexIa processVtx(VertexIa inVtx, uint instanceIdx, float4x4 objTrans, uint vertexID) {
    #ifdef MFT_FlexMeshVisibility
        inVtx.visibility *= (half)unpackColor(flexmeshAlphaBuffer[inVtx.color.a * 255].diffColors[3]).a;
    #endif
    #ifdef MFT_Foliage
        foliageProcessVert( inVtx.pos, inVtx.visibility, inVtx.texCoords, inVtx.normal, inVtx.tangent.xyz, eyePosWorld, vertexID );
    #endif
    #ifdef MFT_WindEffect
        const float3 windDirAndSpeed = getInstanceData(instanceIdx).windDirAndSpeed;
        [branch] if ( any( windDirAndSpeed ) ) {
            inVtx.pos = windBranchBending( inVtx.pos, inVtx.normal, accumTime, windDirAndSpeed.z, inVtx.color.g, windParams.y, inVtx.color.r, dot( objTrans[3], 1 ), windParams.z, windParams.w, inVtx.color.b );
            inVtx.pos = windTrunkBending( inVtx.pos, windDirAndSpeed.xy, inVtx.pos.z * windParams.x );
        }
    #else
        inVtx.color = toLinearColor(inVtx.color);
    #endif
    return inVtx;
}

VtxOut mainV(vertexIARAW inVtxRaw, svInstanceData instanceData, uint vertexID : SV_VertexID) {
    VtxOut vtxOut;
    vtxOut.instanceId = getInstanceId(instanceData);
    const float4x4 instanceTransform = getInstanceTransform(vtxOut.instanceId);
    const VertexIa vtxIn = processVtx(getVertexIA(inVtxRaw), vtxOut.instanceId, instanceTransform, vertexID);
    vtxOut.texCoords = vtxIn.texCoords;
    vtxOut.color = vtxIn.color;
    vtxOut.visibility = vtxIn.visibility * primVisibility;
    vtxOut.normalWs = normalize(mul((float3x3)instanceTransform, mul((float3x3)localTrans, normalize(vtxIn.normal))));
    vtxOut.tangentWs.xyz = normalize(mul((float3x3)instanceTransform, mul((float3x3)localTrans, normalize(vtxIn.tangent.xyz))));
    vtxOut.tangentWs.w = vtxIn.tangent.w;
    vtxOut.posWs = mul(instanceTransform, mul(localTrans, float4(vtxIn.pos, 1))).xyz;
    const float distance = length(vtxOut.posWs - eyePosWorld);
    vtxOut.posWsLast = vtxOut.posWs;
    vtxOut.posLastSS = 0;
    vtxOut.paraboloidPos = 0;
    vtxOut.meshId = 0;

    #if MFT_FlexMeshVisibility
        vtxOut.meshId = vtxIn.color.a * 255;
    #endif

    const float2 distFade = getInstanceDistanceFade(vtxOut.instanceId);
    #ifdef MFT_InstanceDistanceFade
        vtxOut.visibility *= 1 - saturate( (distance - distFade.y)/(distFade.x - distFade.y) );
    #endif

    #ifdef MFT_ImposterCapture
        // TODO some systems dont have affine instance matrices
        const float4x4 localToScreenM = mul(cameraToScreen, mul(worldToCamera, instanceTransform));
        vtxOut.svPos =  mul(localToScreenM, mul(localTrans, float4(vtxIn.pos, 1)));
    #elif MFT_BillboardTransform
        float4x4 vtxToWorldPos0 = mul(subMatrixPosition(instanceTransform, eyePosWorld), localTrans);
        vtxToWorldPos0 = getBillboardTransform(vtxToWorldPos0, diffuseEyePosWorld - eyePosWorld, primFlags & PrimFlag_BillBoardTransformZAxis);
        vtxOut.svPos =  mul(worldToScreenPos0, mul(vtxToWorldPos0, float4(vtxIn.pos, 1)));
    #else
        const float4x4 localToScreenM = mul(worldToScreenPos0, subMatrixPosition(instanceTransform, eyePosWorld));
        vtxOut.svPos =  mul(localToScreenM, mul(localTrans, float4(vtxIn.pos, 1)));
    #endif

    #ifdef MFT_ParaboloidVertTransform
        // paraboloid camera is not affine
        vtxOut.svPos =  mul(mul(worldToCamera, instanceTransform), mul(localTrans, float4(vtxIn.pos, 1))).xzyw;
        paraboloidVert(vtxOut.svPos, vtxOut.paraboloidPos.xyz);
    #endif

    #ifdef MFT_FlexMeshPropVelocity
        vtxOut.posWsLast = mul(vehicleVelocityData[0].lastTransform, mul(localTrans, float4(vtxIn.pos, 1))).xyz;
        vtxOut.posLastSS = mul(viewProjPrevFrame, float4(vtxOut.posWsLast, 1));
        vtxOut.posLastSS.z = (1 - (clamp(length(vtxIn.pos.xyz) / vehicleVelocityData[0].spawnSphereRadius, 1, 2) - 1));
        vtxOut.posLastSS = (vehicleVelocityData[0].spawnSphereRadius > 0) ? vtxOut.posLastSS : vtxOut.svPos;
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

    const MaterialLayer layer = processLayers(vtx, isFrontFacing);

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

    #if defined(MFT_IsTranslucent_PreMulAlpha)
        material.baseColor *= material.opacity;
    #endif

    material.diffColor = saturate((1 - material.metallic) * material.baseColor);
    material.specColor = max(0.001, saturate(lerp(0.04, material.baseColor, material.metallic)));

    material.geomNormalWS = vtx.normalWs;
    material.positionWS = vtx.posWs;
    material.positionLastWS = vtx.posWsLast;
    material.texCoords = vtx.texCoords;
    material.positionSS = vtx.posSS;
    material.positionLastSS = vtx.posLastSS;
    material.vpos = vtx.svPos;
    material.instanceId = vtx.instanceId;
    material.visibility = (half)vtx.visibility;
    material.lightIds = getInstanceLightIds(vtx.instanceId);
    material.layerCount = MFT_MATERIAL_LAYER_COUNT;
    material.annotationColor = 0;

    #if defined(MFT_FlexMeshVisibility)
        material.annotationColor = (half4)unpackColor(flexmeshAlphaBuffer[vtx.meshId].annotationColorPacked);
    #endif

    return processMaterial(material);
    // return newProcessMaterial(material);
}
