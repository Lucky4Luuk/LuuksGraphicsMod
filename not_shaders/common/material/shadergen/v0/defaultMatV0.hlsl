
#define CUSTOM_MATERIAL_BLOCK float cubemapReflectivity;

#include "../shadergen.h.hlsl"
#ifdef MFT_WindEffect
#include "shaders/common/wind.hlsl"
#endif
#ifdef MFT_Foliage
#include "shaders/common/foliage.hlsl"
#endif
#include "shaders/common/vehicle/vehiclePartData.h.hlsl"

#define MATERIAL_V0_TEXTURE_DIFFUSE_IDX 0
#define MATERIAL_V0_TEXTURE_DIFFUSE_DETAIL_IDX 1
#define MATERIAL_V0_TEXTURE_OVERLAY_IDX 2
#define MATERIAL_V0_TEXTURE_NORMAL_IDX 3
#define MATERIAL_V0_TEXTURE_NORMAL_DETAIL_IDX 4
#define MATERIAL_V0_TEXTURE_SPECULAR_IDX 5
#define MATERIAL_V0_TEXTURE_OPACITY_IDX 6
#define MATERIAL_V0_TEXTURE_REFLECTIVITY_IDX 7
#define MATERIAL_V0_TEXTURE_PALETTE_IDX 8
#define MATERIAL_V0_TEXTURE_ANNOTATION_IDX 9
#define MATERIAL_V0_TEXTURES_PER_LAYER 12
#define MATERIAL_V0_TEXTURES_MAX 24

TextureCube cubemap : REGISTER(t9, space1);
StructuredBuffer<VehiclePart> flexmeshAlphaBuffer : REGISTER(t10, space1);
StructuredBuffer<VehicleVelocityDataBuffer> vehicleVelocityData : REGISTER(t11, space1);
Texture2D materialTexture[MATERIAL_V0_TEXTURES_MAX] : REGISTER(t12, space1);


TextureCube getCustomCubemap() {
    return cubemap;
}

#if BNG_HLSL_MODEL < 6
uint getMaterialTexIdx(uint layer, uint textureType, uint textureIdx) {
    const uint arrayTex[] = TEXTURE_IDX_ARRAY;
    return arrayTex[((MATERIAL_V0_TEXTURES_PER_LAYER * layer) + textureType)];
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

void getColorPaletteV0(float4 colorPaletteSample, uint instanceIdx, uint flags, inout float4 baseColor) {
    float4 colorPalette = 0;
    colorPaletteSample.rgb = colorPaletteSample.rgb / (colorPaletteSample.r + colorPaletteSample.g + colorPaletteSample.b + 1e-10);
    float diffA = max(abs(ddx(colorPaletteSample.a)), abs(ddy(colorPaletteSample.a)));
    colorPaletteSample.a = 1 - pow(1 - saturate(colorPaletteSample.a), (diffA > 0.5) ? 4 : 1);
    colorPaletteSample.rgb *= colorPaletteSample.a ;
    colorPaletteSample.a = 1 - colorPaletteSample.a ;

    {
        // base color
        const uint4 instanceColors = getInstanceBaseColors(instanceIdx);
        colorPalette += colorPaletteSample.r * alphaDouble(unpackColor(instanceColors[0]));
        colorPalette += colorPaletteSample.g * alphaDouble(unpackColor(instanceColors[1]));
        colorPalette += colorPaletteSample.b * alphaDouble(unpackColor(instanceColors[2]));
        colorPalette += colorPaletteSample.a * float4(1, 1, 1, 1);
        baseColor *= saturate(colorPalette);
    }
}

struct MaterialLayer {
    float4 diffuseColor;
    float3 specularColor;
    float roughness;
    float3 emissive;
    half3 normal;
    half cubemapReflectivity;
};

struct VtxOut {
    float4 svPos : SV_POSITION;
    float4 posSS : POSITION0; // this is in clip space
    float4 posLastSS : POSITION1;
    float3 posWs : TEXCOORD0;
    float4 color : COLOR0;
    float3 normalWs : NORMAL;
    float4 tangentWs : TANGENT;
    float4 texCoords : TEXCOORD1;
    uint instanceId : TEXCOORD2;
    float visibility : TEXCOORD3;
    float3 paraboloidPos : TEXCOORD4;

    #ifdef MFT_ClipPlane0
        float ClipDistance0   : SV_ClipDistance0;
    #endif
};

MaterialLayer processLayers(VtxOut vtx, bool isFrontFacing) {
    MaterialLayer outLayer = (MaterialLayer)0;
    outLayer.diffuseColor = 1;
    outLayer.normal = half3(0, 0, 1);
    [unroll]
    for(uint layerIdx = 0; layerIdx < MFT_MATERIAL_LAYER_COUNT; ++layerIdx) {
        const uint layerFlags = materialLayerUniforms[layerIdx].flags;
        MaterialLayer inLayer = (MaterialLayer)0;
        inLayer.diffuseColor = 1;
        inLayer.normal = half3(0, 0, 1);
        float4 texCoords = vtx.texCoords;
        if(layerFlags & MATERIAL_LAYER_FLAG_texCoordAnim) {
            texCoords.xy = mul(materialLayerUniforms[layerIdx].texMat, float4(texCoords.xy, 1, 1)).xy;
            texCoords.zw = mul(materialLayerUniforms[layerIdx].texMat, float4(texCoords.zw, 1, 1)).xy;
        }

        // texture samples
        half4 diffuseMapSample = 1;
        [branch] if(materialLayerUniforms[layerIdx].diffuseMapIdx > 0) {
            const uint texIdx = getMaterialTexIdx(layerIdx, MATERIAL_V0_TEXTURE_DIFFUSE_IDX, materialLayerUniforms[layerIdx].diffuseMapIdx);
            diffuseMapSample = (half4)getMaterialTex(texIdx).Sample(defaultSampler2D, getTexCoord(layerFlags, MATERIAL_LAYER_FLAG_diffuseMapUV1, texCoords));
        }
        half opacityMapSample = 1;
        [branch] if(materialLayerUniforms[layerIdx].opacityMapIdx > 0) {
            const uint texIdx = getMaterialTexIdx(layerIdx, MATERIAL_V0_TEXTURE_OPACITY_IDX, materialLayerUniforms[layerIdx].opacityMapIdx);
            opacityMapSample = (half)getMaterialTex(texIdx).Sample(defaultSampler2D, getTexCoord(layerFlags, MATERIAL_LAYER_FLAG_opacityMapUV1, texCoords)).r;
        }
        half4 overlayMapSample = 0;
        [branch] if(materialLayerUniforms[layerIdx].overlayMapIdx > 0) {
            const uint texIdx = getMaterialTexIdx(layerIdx, MATERIAL_V0_TEXTURE_OVERLAY_IDX, materialLayerUniforms[layerIdx].overlayMapIdx);
            overlayMapSample = (half4)getMaterialTex(texIdx).Sample(defaultSampler2D, getTexCoord(layerFlags, MATERIAL_LAYER_FLAG_overlayMapUV1, texCoords));
        }
        half4 normalMapSample = 0;
        [branch] if(materialLayerUniforms[layerIdx].normalMapIdx > 0) {
            const uint texIdx = getMaterialTexIdx(layerIdx, MATERIAL_V0_TEXTURE_NORMAL_IDX, materialLayerUniforms[layerIdx].normalMapIdx);
            normalMapSample = (half4)getMaterialTex(texIdx).Sample(defaultSampler2D, getTexCoord(layerFlags, MATERIAL_LAYER_FLAG_normalMapUV1, texCoords));
        }
        half3 specMapSample = 1;
        [branch] if(materialLayerUniforms[layerIdx].specularMapIdx > 0) {
            const uint texIdx = getMaterialTexIdx(layerIdx, MATERIAL_V0_TEXTURE_SPECULAR_IDX, materialLayerUniforms[layerIdx].specularMapIdx);
            specMapSample = (half3)getMaterialTex(texIdx).Sample(defaultSampler2D, getTexCoord(layerFlags, MATERIAL_LAYER_FLAG_specularMapUV1, texCoords)).xyz;
        }
        half reflectivityMapSample = 0;
        [branch] if((layerIdx == 0) && (materialLayerUniforms[layerIdx].reflectivityMapIdx > 0)) {
            const uint texIdx = getMaterialTexIdx(layerIdx, MATERIAL_V0_TEXTURE_REFLECTIVITY_IDX, materialLayerUniforms[layerIdx].reflectivityMapIdx);
            reflectivityMapSample = (half)getMaterialTex(texIdx).Sample(defaultSampler2D, getTexCoord(layerFlags, MATERIAL_LAYER_FLAG_reflectivityMapUV1, texCoords)).a;
        }
        half4 colorPaletteMapSample = half4(0, 0, 0, 1);
        [branch] if(materialLayerUniforms[layerIdx].colorPaletteTexIdx > 0) {
            const uint texIdx = getMaterialTexIdx(layerIdx, MATERIAL_V0_TEXTURE_PALETTE_IDX, materialLayerUniforms[layerIdx].colorPaletteTexIdx);
            colorPaletteMapSample = (half4)getMaterialTex(texIdx).Sample(defaultSampler2D, getTexCoord(layerFlags, MATERIAL_LAYER_FLAG_colorPaletteMapUV1, texCoords));
        }

        // detail
        half4 diffuseDetailMapSample = 0.5;
        half4 normalDetailMapSample = 0;
        {
            float4 detTexCoords = vtx.texCoords * float4(materialLayerUniforms[layerIdx].detailScale, materialLayerUniforms[layerIdx].detailScale);
            if(layerFlags & MATERIAL_LAYER_FLAG_texCoordAnim) {
                detTexCoords.xy = mul(materialLayerUniforms[layerIdx].texMat, float4(detTexCoords.xy, 1, 1)).xy;
                detTexCoords.zw = mul(materialLayerUniforms[layerIdx].texMat, float4(detTexCoords.zw, 1, 1)).xy;
            }

            [branch] if(materialLayerUniforms[layerIdx].detailMapIdx > 0) {
            const uint texIdx = getMaterialTexIdx(layerIdx, MATERIAL_V0_TEXTURE_DIFFUSE_DETAIL_IDX, materialLayerUniforms[layerIdx].detailMapIdx);
                diffuseDetailMapSample = (half4)getMaterialTex(texIdx).Sample(defaultSampler2D, getTexCoord(layerFlags, MATERIAL_LAYER_FLAG_detailMapUV1, detTexCoords));
            }
            [branch] if(materialLayerUniforms[layerIdx].normalDetailMapIdx > 0) {
            const uint texIdx = getMaterialTexIdx(layerIdx, MATERIAL_V0_TEXTURE_NORMAL_DETAIL_IDX, materialLayerUniforms[layerIdx].normalDetailMapIdx);
                normalDetailMapSample = (half4)getMaterialTex(texIdx).Sample(defaultSampler2D, getTexCoord(layerFlags, MATERIAL_LAYER_FLAG_normalDetailMapUV1, detTexCoords));
            }
        }

        inLayer.diffuseColor = materialLayerUniforms[layerIdx].diffuseColor * ((layerFlags & MATERIAL_LAYER_FLAG_vtxColorToBaseColor) ? vtx.color : 1);
        inLayer.diffuseColor *= saturate(diffuseMapSample + (diffuseDetailMapSample * 2 - 1));
        inLayer.diffuseColor.rgb = lerp( inLayer.diffuseColor.rgb, overlayMapSample.rgb, overlayMapSample.a );
        inLayer.diffuseColor.a *= opacityMapSample;

        // instance color
        if(materialLayerUniforms[layerIdx].colorPaletteTexIdx <= 0) {
            const half4 instanceColor0 = (half4)unpackColor(getInstanceBaseColors(vtx.instanceId)[0]);
            inLayer.diffuseColor *= (layerFlags & MATERIAL_LAYER_FLAG_instanceBaseColor) ? instanceColor0 : 1;
        }
        else {
            getColorPaletteV0(colorPaletteMapSample, vtx.instanceId, layerFlags, inLayer.diffuseColor);
        }

        inLayer.specularColor = materialLayerUniforms[layerIdx].specularColor.xyz;
        inLayer.specularColor *= specMapSample;
        inLayer.normal = (materialLayerUniforms[layerIdx].normalMapIdx > 0) ? decodeNormal(normalMapSample, materialLayerUniforms[layerIdx].flags) : inLayer.normal;
        inLayer.normal = (half3)normalize(inLayer.normal * float3(materialLayerUniforms[layerIdx].normalMapStrength.xx, 1));
        if(materialLayerUniforms[layerIdx].normalDetailMapIdx > 0) {
            inLayer.normal.xy += (half2)(decodeNormal(normalDetailMapSample, materialLayerUniforms[layerIdx].flags).xy * materialLayerUniforms[layerIdx].normalDetailMapStrength);
            inLayer.normal = normalize(inLayer.normal);
        }

        inLayer.roughness = materialLayerUniforms[layerIdx].roughnessFactor;
        if(materialLayerUniforms[layerIdx].reflectivityMapIdx > 0) {
            inLayer.cubemapReflectivity = (half)saturate(materialLayerUniforms[layerIdx].reflectivityMapFactor) * reflectivityMapSample;
            #ifdef MFT_FlexMeshVisibility
                inLayer.cubemapReflectivity = (half)pow(inLayer.cubemapReflectivity, 2);
            #endif
        }
        else {
            #ifdef MFT_FlexMeshVisibility
                if(!(materialLayerUniforms[layerIdx].flags & MATERIAL_LAYER_FLAG_emissive)) {
                    float p = (layerIdx == 0) ? 1 : 0.25;
                    inLayer.diffuseColor.a = pow(inLayer.diffuseColor.a, p);
                }
            #endif
            inLayer.cubemapReflectivity = (layerIdx == 0) ? (half)inLayer.diffuseColor.a : 0;
        }

        if(layerIdx == 0) {
            #if MFT_CubeMap
                inLayer.diffuseColor.rgb = lerp(inLayer.diffuseColor.rgb, 0, inLayer.cubemapReflectivity);
                inLayer.specularColor.rgb = lerp(inLayer.specularColor.rgb, 0, inLayer.cubemapReflectivity);
            #endif
        }

        #ifdef MFT_GlowMask
            inLayer.diffuseColor.rgb *= materialLayerUniforms[layerIdx].glowFactor;
            inLayer.specularColor.rgb *= materialLayerUniforms[layerIdx].glowFactor;
        #endif

        if(materialLayerUniforms[layerIdx].flags & MATERIAL_LAYER_FLAG_emissive) {
            inLayer.emissive = inLayer.diffuseColor.rgb;
            inLayer.diffuseColor.rgb = 0;
            inLayer.specularColor.rgb = 0;
        }

        const half layerBlendFactor = (layerIdx == 0) ? 1 : (half)inLayer.diffuseColor.a;
        outLayer.diffuseColor = lerp(outLayer.diffuseColor, inLayer.diffuseColor, layerBlendFactor);
        outLayer.specularColor = lerp(outLayer.specularColor, inLayer.specularColor, layerBlendFactor);
        outLayer.emissive = lerp(outLayer.emissive, inLayer.emissive, layerBlendFactor);
        outLayer.normal = lerp(outLayer.normal, inLayer.normal, layerBlendFactor);
        outLayer.roughness = lerp(outLayer.roughness, inLayer.roughness, layerBlendFactor);
        outLayer.cubemapReflectivity = saturate(lerp(outLayer.cubemapReflectivity, inLayer.cubemapReflectivity, layerBlendFactor));
    }
    outLayer.diffuseColor = toLinearColor(outLayer.diffuseColor);
    outLayer.specularColor = toLinearColor(outLayer.specularColor);

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
        inVtx.color = inVtx.color;
    #endif

    return inVtx;
}

VtxOut mainV(vertexIARAW inVtxRaw, svInstanceData instanceData, uint vertexID : SV_VertexID) {
    VtxOut vtxOut = (VtxOut)0;
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
    const float4x4 localToCameraM = mul(worldToCameraPos0, subMatrixPosition(instanceTransform, eyePosWorld));
    vtxOut.svPos = mul(cameraToScreen, mul(localToCameraM, mul(localTrans, float4(vtxIn.pos, 1))));
    vtxOut.posSS = vtxOut.svPos;
    vtxOut.posLastSS = vtxOut.svPos;
    vtxOut.paraboloidPos = 0;

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

    #ifdef MFT_ClipPlane0
        vtxOut.ClipDistance0 = dot(float4(vtxOut.posWs, 1), clipPlane0);
    #endif


    return vtxOut;
}

Fragout mainP(VtxOut vtx, bool isFrontFacing : SV_IsFrontFace) {
    const MaterialLayer layer = processLayers(vtx, isFrontFacing);

    vtx.normalWs = normalize(vtx.normalWs);
    vtx.tangentWs.xyz = normalize(vtx.tangentWs.xyz);

    Material material = (Material)0;
    material.baseColor = layer.diffuseColor.xyz;
    material.metallic = 0;
    material.opacity = layer.diffuseColor.a;
    material.roughness = layer.roughness;
    material.ambientOclussion = 1;
    material.emissive = layer.emissive;
    material.clearCoat = 0;
    material.clearCoatRoughness = 0;
    material.normalsWS = mul(getTangentToWorldNormalMatrix(vtx.normalWs, vtx.tangentWs), layer.normal);
    material.clearCoat2ndNormalWS = material.normalsWS;
    material.cubemapReflectivity = layer.cubemapReflectivity;

    material.diffColor = layer.diffuseColor.xyz;
    material.specColor = layer.specularColor.xyz;

    material.geomNormalWS = vtx.normalWs;
    material.positionWS = vtx.posWs;
    material.positionLastWS = vtx.posWs;
    material.texCoords = vtx.texCoords;
    material.positionSS = vtx.posSS;
    material.positionLastSS = vtx.posLastSS;
    material.vpos = vtx.svPos;
    material.instanceId = vtx.instanceId;
    material.visibility = (half)vtx.visibility;
    material.lightIds = getInstanceLightIds(vtx.instanceId);
    material.layerCount = MFT_MATERIAL_LAYER_COUNT;

    return processMaterial(material);
}
