
#ifndef _MATERIAL_H_HLSL_
#define _MATERIAL_H_HLSL_

#define MaterialFlagDeprecated (1 << 0)

struct Material {
    float3 baseColor;
    float metallic;
    float3 normalsWS;
    float roughness;
    float3 positionWS;
    float3 positionLastWS;
    float opacity;
    float4 texCoords;
    float clearCoat;
    float clearCoatRoughness;
    float ambientOclussion;
    uint layerCount;
    float3 emmisive;
    uint flags;
    uint2 maxTexSize;
    uint2 minTexSize;

    float4 positionSS;
    float4 positionLastSS;
    float4 vpos;
    float3 diffColor;
    float3 specColor;
    float3 geomNormalWS;
    float3 emissive;
    uint instanceId;
    uint4 lightIds;
    float3 clearCoat2ndNormalWS;
    half visibility;
    half4 annotationColor;

    #ifdef CUSTOM_MATERIAL_BLOCK
        CUSTOM_MATERIAL_BLOCK
    #endif
};

struct MaterialUniforms_1_5 {
    uint flags;
    float alphaTestValue;
    uint annotationColorPacked;
    uint padding0;
    float4 imposterLimits;
    float4 imposterUVs;
};

struct MaterialLayerUniforms_1_5 {
    float3 baseColor;
    float opacity;
    float3 emissive;
    float roughness;
    float metallic;
    float ao;
    float clearCoat;
    float clearCoatRoughness;
    float clearCoatBottomNormalMapStrength;
    float normalMapStrength;
    float normalDetailMapStrength;
    uint flags;
    float2 detailScale;
    uint opacityTexIdx;
    uint normalTexIdx;
    uint baseColorTexIdx;
    uint metallicTexIdx;
    uint roughnessTexIdx;
    uint aoTexIdx;
    uint emissiveTexIdx;
    uint baseColorDetailTexIdx;
    uint normalDetailTexIdx;
    uint colorPaletteTexIdx;
    uint clearCoatTexIdx;
    uint clearCoatRoughnessTexIdx;
    uint2 padding0;
    float4x4 texureAnimM;
};


struct MaterialUniforms_1_0 {
    float4 subSurfaceParams;
    float4 imposterLimits;
    float4 imposterUVs;
    float4 materialAnnotation;
    float3 padding0;
    float minnaertConstant;

    uint flags;
    float alphaTestValue;
    float parallaxInfo;
    float padding1;

    // terrain
    float4 annotationColorBlend;
    float layerSize;
    float squareSize;
    float oneOverTerrainSize;
    float padding2;
};

struct MaterialLayerUniforms_1_0 {
    float4 diffuseColor;
    float4 specularColor;
    float4 bumpAtlasParams;
    float4 bumpAtlasTileParams;
    float4 diffuseAtlasParams;
    float4 diffuseAtlasTileParams;

    float2 detailScale;
    uint flags;
    float roughnessFactor;

    float normalMapStrength;
    float normalDetailMapStrength;
    float reflectivityMapFactor;
    uint diffuseMapIdx;

    uint detailMapIdx;
    uint overlayMapIdx;
    uint normalMapIdx;
    uint normalDetailMapIdx;

    uint specularMapIdx;
    uint opacityMapIdx;
    uint reflectivityMapIdx;
    uint colorPaletteTexIdx;

    float3 glowFactor;
    uint annotationMapIdx;

    float4x4 texMat;

    // terrain
    float4 detailScaleAndFade;
    float4 macroScaleAndFade;
    float3 annotationColor;
    float padding1;
    float3 macroIdStrengthParallax;
    float padding2;
    float3 detailIdStrengthParallax;
    float padding3;
};


#endif // _MATERIAL_H_HLSL_
