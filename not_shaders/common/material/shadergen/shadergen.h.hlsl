#ifndef _SHADERGEN_H_HLSL_
#define _SHADERGEN_H_HLSL_

#define BNG_USE_SCENE_CBUFFER
#define BNG_SHADERGEN

#ifdef SHADER_STAGE_VS
#define mainV main
#else
#define mainP main
#endif

#if !defined(MFT_AlphaTest) && (defined(MFT_AlphaTest0) || defined(MFT_AlphaTest1) || defined(MFT_AlphaTest2) || defined(MFT_AlphaTest3))
#define MFT_AlphaTest 1
#endif

#if !defined(MFT_Clearcoat) && (defined(MFT_Clearcoat0) || defined(MFT_Clearcoat1) || defined(MFT_Clearcoat2) || defined(MFT_Clearcoat3))
#define MFT_Clearcoat 1
#endif


#ifndef BIT
#define BIT(x) (1 << x)
#endif

#define MATERIAL_LAYER_FLAG_diffuseMapUV1       BIT(0)
#define MATERIAL_LAYER_FLAG_overlayMapUV1       BIT(1)
#define MATERIAL_LAYER_FLAG_lightMapUV1         BIT(2)
#define MATERIAL_LAYER_FLAG_detailMapUV1        BIT(3)
#define MATERIAL_LAYER_FLAG_normalMapUV1        BIT(4)
#define MATERIAL_LAYER_FLAG_normalDetailMapUV1  BIT(5)
#define MATERIAL_LAYER_FLAG_opacityMapUV1       BIT(6)
#define MATERIAL_LAYER_FLAG_colorPaletteMapUV1  BIT(7)
#define MATERIAL_LAYER_FLAG_specularMapUV1      BIT(8)
#define MATERIAL_LAYER_FLAG_reflectivityMapUV1  BIT(9)
#define MATERIAL_LAYER_FLAG_emissiveMapUV1      BIT(10)
#define MATERIAL_LAYER_FLAG_roughnessMapUV1     BIT(11)
#define MATERIAL_LAYER_FLAG_metallicMapUV1      BIT(12)
#define MATERIAL_LAYER_FLAG_clearCoatMapUV1     BIT(13)
#define MATERIAL_LAYER_FLAG_aoMapUV1            BIT(14)
#define MATERIAL_LAYER_FLAG_normalMapBC5        BIT(15)
#define MATERIAL_LAYER_FLAG_normalMap3Dc        BIT(16)
#define MATERIAL_LAYER_FLAG_normalMapDXT5       BIT(17)
#define MATERIAL_LAYER_FLAG_instanceBaseColor   BIT(18)
#define MATERIAL_LAYER_FLAG_instanceEmissive    BIT(19)
#define MATERIAL_LAYER_FLAG_vtxColorToBaseColor BIT(20)
#define MATERIAL_LAYER_FLAG_emissive            BIT(21)
#define MATERIAL_LAYER_FLAG_texCoordAnim        BIT(22)

#include "shaders/common/bng.hlsl"
#include "vertexIA.h.hlsl"
#if !defined(MFT_MaterialDeprecated)
#include "permutations.h.hlsl"
#else
#include "v0/permutationsV0.h.hlsl"
#endif

struct svInstanceData {
    uint svInstanceID : SV_InstanceID;
#if BNG_HLSL_MODEL >= 6
    [[vk::builtin("BaseInstance")]] uint svInstanceBaseID : A;
#endif
};

uint getInstanceId(svInstanceData instanceData) {
    return instanceData.svInstanceID
#if BNG_HLSL_MODEL >= 6
     + instanceData.svInstanceBaseID;
#else
    + instanceBase;
#endif
}

float4x4 getInstanceTransform(uint instanceIdx) {
    #if defined(MFT_UseInstancing)
        return instancesBuffer[instanceIdx].uObjectTrans;
    #else
        return uObjectTrans;
    #endif
}

uint4 getInstanceLightIds(uint instanceIdx) {
    #if defined(MFT_UseInstancing)
        return instancesBuffer[instanceIdx].lightIds;
    #else
        return inLightId;
    #endif
}

uint4 getInstanceBaseColors(uint instanceIdx) {
    #if defined(MFT_UseInstancing)
        return instancesBuffer[instanceIdx].instanceColors;
    #else
        return instanceColors;
    #endif
}

float2 getInstanceDistanceFade(uint instanceIdx) {
    #if defined(MFT_UseInstancing)
        return instancesBuffer[instanceIdx].distanceFadeParams;
    #else
        return distanceFadeParams;
    #endif
}

void getColorPalette(float4 colorPaletteSample, uint4 instanceColors, uint4 instanceDataPacked, uint flags, inout float3 baseColor, inout float3 emissive, inout float roughness, inout float metallic, inout float clearCoat, inout float clearCoatRouhness) {
    float4 colorPalette = 0;
    colorPaletteSample.rgb = colorPaletteSample.rgb / (colorPaletteSample.r + colorPaletteSample.g + colorPaletteSample.b + 1e-10);
    float diffA = max(abs(ddx(colorPaletteSample.a)), abs(ddy(colorPaletteSample.a)));
    colorPaletteSample.a = 1 - pow(1 - saturate(colorPaletteSample.a), (diffA > 0.5) ? 4 : 1);
    colorPaletteSample.rgb *= colorPaletteSample.a ;
    colorPaletteSample.a = 1 - colorPaletteSample.a ;

    {
        // base color
        colorPalette += colorPaletteSample.r * alphaDouble(toLinearColor(unpackColor(instanceColors[0])));
        colorPalette += colorPaletteSample.g * alphaDouble(toLinearColor(unpackColor(instanceColors[1])));
        colorPalette += colorPaletteSample.b * alphaDouble(toLinearColor(unpackColor(instanceColors[2])));
        colorPalette += colorPaletteSample.a * float4(1, 1, 1, 1);
        baseColor *= colorPalette.rgb;
        if(flags & MaterialFlag_instanceEmissive) {
            emissive *= colorPalette.rgb;
        }
    }

    {
        // material data
        float4 instanceData = 0;
        instanceData += colorPaletteSample[0] * unpackColor(instanceDataPacked[0]);
        instanceData += colorPaletteSample[1] * unpackColor(instanceDataPacked[1]);
        instanceData += colorPaletteSample[2] * unpackColor(instanceDataPacked[2]);
        instanceData += colorPaletteSample[3] * unpackColor(instanceDataPacked[3]);
        roughness *= instanceData[0];
        metallic *= instanceData[1];
        clearCoat *= instanceData[2];
        clearCoatRouhness *= instanceData[3];
    }
}

void getColorPalette(float4 colorPaletteSample, uint instanceIdx, uint flags, inout float3 baseColor, inout float3 emissive, inout float roughness, inout float metallic, inout float clearCoat, inout float clearCoatRouhness) {
    float4 colorPalette = 0;
    colorPaletteSample.rgb = colorPaletteSample.rgb / (colorPaletteSample.r + colorPaletteSample.g + colorPaletteSample.b + 1e-10);
    float diffA = max(abs(ddx(colorPaletteSample.a)), abs(ddy(colorPaletteSample.a)));
    colorPaletteSample.a = 1 - pow(1 - saturate(colorPaletteSample.a), (diffA > 0.5) ? 4 : 1);
    colorPaletteSample.rgb *= colorPaletteSample.a ;
    colorPaletteSample.a = 1 - colorPaletteSample.a ;

    {
        // base color
        const uint4 instanceColors = getInstanceBaseColors(instanceIdx);
        colorPalette += colorPaletteSample.r * alphaDouble(toLinearColor(unpackColor(instanceColors[0])));
        colorPalette += colorPaletteSample.g * alphaDouble(toLinearColor(unpackColor(instanceColors[1])));
        colorPalette += colorPaletteSample.b * alphaDouble(toLinearColor(unpackColor(instanceColors[2])));
        colorPalette += colorPaletteSample.a * float4(1, 1, 1, 1);
        baseColor *= colorPalette.rgb;
        if(flags & MaterialFlag_instanceEmissive) {
            emissive *= colorPalette.rgb;
        }
    }

    {
        // material data
        uint4 instanceDataPacked = getInstanceData(instanceIdx).instanceCustomData;
        float4 instanceData = 0;
        instanceData += colorPaletteSample[0] * unpackColor(instanceDataPacked[0]);
        instanceData += colorPaletteSample[1] * unpackColor(instanceDataPacked[1]);
        instanceData += colorPaletteSample[2] * unpackColor(instanceDataPacked[2]);
        instanceData += colorPaletteSample[3] * unpackColor(instanceDataPacked[3]);
        roughness *= instanceData[0];
        metallic *= instanceData[1];
        clearCoat *= instanceData[2];
        clearCoatRouhness *= instanceData[3];
    }
}

float3x3 getTangentToWorldNormalMatrix(float3 normalWs, float4 tangentWs) {
    float3 T = /*normalize*/(tangentWs.xyz);
    float3 N = /*normalize*/(normalWs);
    float3 B = /*normalize*/(cross( N, T ) * tangentWs.w);
    float3x3 tangentToWs;
    // set collumns TBN
    tangentToWs._m00_m10_m20 = T;
    tangentToWs._m01_m11_m21 = B;
    tangentToWs._m02_m12_m22 = N;
    return tangentToWs;
}

half3 decodeNormal(float2 n) {
    n = n * 2 - 1;
    float3 normal = float3(n, sqrt( 1.0 - saturate(dot( n, n )) ));
    normal.y = -normal.y; // normal format
    return (half3)normalize(normal);
}

half3 decodeNormal(half4 n, uint flags) {
    if(flags & MATERIAL_LAYER_FLAG_normalMapDXT5) {
        return decodeNormal(n.ag);
    }
    else if(flags & MATERIAL_LAYER_FLAG_normalMap3Dc) {
        return decodeNormal(n.gr);
    }
    else if(flags & MATERIAL_LAYER_FLAG_normalMapBC5) {
        return decodeNormal(n.rg);
    }
    n = half4(normalize(n.xyz * 2 - 1), 1);
    n.y = -n.y; // normal format
    return n.xyz;
}

void paraboloidVert(inout float4 hpos, out float3 paraboloidPos) {
    float L = length(hpos.xyz);
    const bool isBack = hpos.z < 0.0;
    paraboloidPos.z = isBack ? -1.0 : 1.0;
    if ( isBack ) hpos.z = -hpos.z;
    hpos /= L;
    hpos.z = hpos.z + 1.0;
    hpos.xy /= hpos.z;
    hpos.z = L / lightParams.x;
    hpos.w = 1.0;
    paraboloidPos.xy = hpos.xy;
    hpos.xy *= atlasScale.xy;
    hpos.x += isBack ? 0.5 : -0.5;
    hpos.z = 1.0f - hpos.z; // reversed depth buffer
}

#endif //_SHADERGEN_H_HLSL_
