#ifndef _SHADERGEN_PERMUTATION_H_HLSL_
#define _SHADERGEN_PERMUTATION_H_HLSL_

#include "shaders/common/lighting.hlsl"
#include "shaders/common/lighting/shadowMap/shadowMapPSSM.h.hlsl"

TextureCube getCustomCubemap();

float4 calculateDeferredRTLighting(inout Material material, float4 screenspacePos, out float d_NL_Att) {
    float2 uvScene = screenspacePos.xy / screenspacePos.w;
    uvScene = ( uvScene + 1.0 ) / 2.0;
    uvScene.y = 1.0 - uvScene.y;
    uvScene = ( uvScene * lightInfoBufferParams.zw ) + lightInfoBufferParams.xy;
    float3 d_lightcolor;
    float3 d_specular;
#ifdef MFT_RTLighting1_5
    lightinfoUncondition(lightInfoBuffer.Sample(defaultSamplerRT, uvScene), lightInfoBuffer1.Sample(defaultSamplerRT, uvScene), d_lightcolor, d_NL_Att, d_specular);
#else
    lightinfoUncondition(lightInfoBuffer.Sample(defaultSamplerRT, uvScene), d_lightcolor, d_NL_Att, d_specular);
#endif

    d_lightcolor *= PI; // TODO ???
    d_specular *= PI; // TODO ???

    float4 outputFinalColor = 0;
    outputFinalColor.w = material.opacity;
    outputFinalColor.rgb += (material.diffColor / PI) * d_lightcolor;
    outputFinalColor.rgb += material.emissive;
    material.ambientOclussion *= (ambientOcclusionBuffer.Sample(defaultSamplerRT, uvScene).r);
#ifdef BNG_ADVANCED_LIGHTING
    outputFinalColor.rgb += (material.diffColor / PI) * calcDiffuseAmbient(getColorSH9(ambientSH9), ambient.rgb, material.normalsWS, ambient.a).rgb * material.ambientOclussion;
#else
    outputFinalColor.rgb += material.diffColor * calcDiffuseAmbient(ambient.rgb, material.normalsWS).rgb * material.ambientOclussion;
#endif

#ifdef MFT_RTLighting1_5
    outputFinalColor.rgb += d_specular;
#else
    outputFinalColor.rgb += material.specColor * d_specular;
#endif

    return outputFinalColor;
}

float3 calculateTRLightingForward(Material material, uint4 inLightId, float3 wsPosition) {
    float3 wsView = normalize( eyePosWorld - wsPosition );
    float4 rtShading; float4 specular;
    float4 shadowMask = float4( 1, 1, 1, 1 );
#if MFT_IsTranslucentRecvShadows
    float3 sunShadowDebugColor;
    shadowMask = float4(calcShadowPSSM(createSamplerTexture2D(defaultSamplerRT, ShadowMap), wsPosition, 0, float2(0.5, 0.5), 1, sunShadowDebugColor), 1, 1, 1);
#endif
    compute4Lights( wsView, wsPosition, material.normalsWS, shadowMask,
        inLightId, material.roughness, float4(material.specColor, 1),
        rtShading, specular );
    float4 outputFinalColor = float4((0).xxx, material.opacity);

    outputFinalColor.rgb = material.diffColor * ( rtShading.rgb + calcDiffuseAmbient(ambient.rgb, material.normalsWS).rgb);
    outputFinalColor.rgb += material.emissive;
    outputFinalColor.rgb += specular.rgb;
    return outputFinalColor.rgb;
}

float3 calculateCubeReflection(Material material, float3 wsPosition, uint instanceID, float3 geomNormWS) {
    float3 eyeToVert = normalize( wsPosition - eyePosWorld );
    float reflectionNorm = (getInstanceData(instanceID).instanceFlags & InstanceFlags_DisabledNormalizeReflection) ? 1 : saturate(hdrLuminance(ambient.rgb + 0.025) * 2);
    float3 reflectionFactor = 1;
    float3 outputFinalColor = 0;

#if !defined(MFT_SceneCubeMap)
    TextureCube refMap = getCustomCubemap();
#else
    TextureCube refMap = sceneCubeSpecMap;
#endif

#if defined(MFT_Clearcoat)
    {
        float3 reflectVec = reflect(eyeToVert, material.normalsWS);
        float horizonVis = any(geomNormWS != material.normalsWS) ? calculateIblHorizonVisibility(reflectVec, geomNormWS) : 1;
        reflectionFactor = material.clearCoat * environmentBRDFAprox((0.04), material.clearCoatRoughness, dot(-eyeToVert, material.clearCoat2ndNormalWS)) * horizonVis;
        outputFinalColor.rgb += ((refMap.SampleLevel( defaultSamplerCube, reflectVec, calculateEnvMipmap(refMap, material.clearCoatRoughness)).rgb) * (1.0)) * reflectionFactor * material.ambientOclussion * reflectionNorm;
        reflectionFactor = 1 - reflectionFactor;
    }
#endif

    {
        float3 reflectVec = reflect(eyeToVert, material.normalsWS);
        float horizonVis = any(geomNormWS != material.normalsWS) ? calculateIblHorizonVisibility(reflectVec, geomNormWS) : 1;
        outputFinalColor.rgb += ((refMap.SampleLevel( defaultSamplerCube, reflectVec, calculateEnvMipmap(refMap, material.roughness)).rgb)) * reflectionFactor
        * environmentBRDFAprox(material.specColor, material.roughness, dot(-eyeToVert, material.normalsWS)) * material.ambientOclussion * horizonVis * reflectionNorm;
    }

    return outputFinalColor;
}


void processVisibility(inout Material material, float2 vPos) {
#ifdef MFT_AlphaTest
    clip(material.opacity - materialUniforms.alphaTestValue);
#endif

#if !defined(MFT_Visibility)
    return;
#endif

    float visibility = 1;
//#if MFT_VisibilityVS
    visibility *= material.visibility;
//#endif

#if MFT_UseInstancing
    visibility *= getInstanceData(material.instanceId).uVisibility;
#else
    visibility *= uVisibility;
#endif

#if MFT_VisibilityPrim
    visibility *= primVisibility;
#endif

    material.opacity *= visibility;

#if !defined(MFT_IsTranslucent) && !defined(MFT_IsTranslucentZWrite)
    // Everything else does a fizzle.
    fizzle( vPos.xy, visibility );
#endif
}

#if defined(MFT_PrePassConditioner)
#include "shaders/common/gbuffer.h"
#define HAS_FRAGOUT
struct Fragout {
   float4 target0 : SV_Target0;
#if MFT_RTLighting1_5
   float4 target1 : SV_Target1;
#endif
};
Fragout processMaterial(Material material) {
    Fragout OUT = (Fragout)0;
    processVisibility(material, material.vpos.xy);
    float4 normal_depth;
    float4 out_spec_none;
    encodeGBuffer(material.normalsWS, material.roughness, material.specColor, material.opacity, normal_depth, out_spec_none);
    normal_depth.a = material.opacity;
    out_spec_none.a = material.opacity;
    OUT.target0 = normal_depth;
#if MFT_RTLighting1_5
    OUT.target1 = out_spec_none;
#endif
    return OUT;
}


#elif defined(MFT_AnnotationColor)
#define HAS_FRAGOUT
struct Fragout {
   float4 target0 : SV_Target0;
};
    Fragout processMaterial(Material material) {
    Fragout OUT = (Fragout)0;

    processVisibility(material, material.vpos.xy);
    #if defined(MFT_IsTranslucent)
        if(material.opacity < 0.5) discard;
    #endif

    if(material.annotationColor.a > 0) {
        OUT.target0 = material.annotationColor;
        return OUT;
    }

    #if defined(MFT_TerrainVertHeight)
        OUT.target0 = float4(material.annotationColor.rgb, 1);
    #elif defined(MFT_ImposterVert)
        OUT.target0 = float4(unpackColor(materialUniforms.annotationColorPacked).rgb, 1);
    #else
        OUT.target0 = unpackColor(getInstanceData(material.instanceId).instanceColors[3]);
        OUT.target0 = float4((OUT.target0.a > 0 ? OUT.target0 : unpackColor(materialUniforms.annotationColorPacked)).rgb, 1);
    #endif

    if(bool(primFlags & PrimFlag_OutputColor)) {
        OUT.target0 = unpackColor(primOutputColor1);
    }
    return OUT;
}

#elif defined(MFT_ProcessMaterialOutput)
#include "shaders/common/postFx/materialDebug/materialDebug.h.hlsl"
#define HAS_FRAGOUT
struct Fragout {
   float4 target0 : SV_Target0;
};
Fragout processMaterial(Material material) {
    Fragout OUT = (Fragout)0;
    processVisibility(material, material.vpos.xy);
    OUT.target0 = processMaterialOutput(material);
    return OUT;
}


#elif defined(MFT_ImposterCapture) && !defined(MFT_NormalsOut)
#define HAS_FRAGOUT
struct Fragout {
   float4 target0 : SV_Target0;
};
Fragout processMaterial(Material material) {
    Fragout OUT = (Fragout)0;
#ifdef MFT_AlphaTest
    clip(material.opacity - materialUniforms.alphaTestValue);
#endif
    OUT.target0 = max(0, float4(material.diffColor, material.opacity));
    OUT.target0.rgb = linearToGammaColor(OUT.target0.rgb);
    return OUT;
}

#elif defined(MFT_ImposterCapture) && defined(MFT_NormalsOut)
#define HAS_FRAGOUT
struct Fragout {
   float4 target0 : SV_Target0;
};
Fragout processMaterial(Material material) {
    Fragout OUT = (Fragout)0;
#ifdef MFT_AlphaTest
    clip(material.opacity - materialUniforms.alphaTestValue);
#endif
    float3 tsNormal = float3(-material.normalsWS.x, material.normalsWS.z, material.normalsWS.y);
    OUT.target0 = max(0, float4(tsNormal * 0.5 + 0.5, material.opacity));
    return OUT;
}

#elif defined(MFT_OutputFinalColor) && !defined(MFT_ForwardShading) && !defined(MFT_MaterialDeprecated)
#include "shaders/common/lighting.hlsl"
#define HAS_FRAGOUT
struct Fragout {
   float4 target0 : SV_Target0;
};
Fragout processMaterial(Material material) {
    // Visibility
     processVisibility(material, material.vpos.xy);

    float4 outputFinalColor = float4(0, 0, 0, material.opacity);

    // Deferred RT Lighting
    #if defined(MFT_RTLighting)
    {
        float d_NL_Att;
        outputFinalColor.rgb += calculateDeferredRTLighting(material, material.positionSS, d_NL_Att).rgb;
    }
    #endif

    #if MFT_CubeMap
    {
        // Reflect Cube
        float3 eyeToVert = normalize( material.positionWS - eyePosWorld );
        float3 reflectVec = reflect(eyeToVert, material.normalsWS);
        uint instFlags;
        #if MFT_UseInstancing
            instFlags = getInstanceData(material.instanceId).instanceFlags;
        #else
            instFlags = instanceFlags;
        #endif
        float reflectionNorm = (instFlags & InstanceFlags_DisabledNormalizeReflection) ? 1 : saturate(hdrLuminance(ambient.rgb + 0.025) * 2);
        outputFinalColor.rgb += calculateCubeReflection(material, material.positionWS, material.instanceId, material.geomNormalWS);
    }
    #endif

    // HDR Output
    Fragout OUT = (Fragout)0;
    OUT.target0 = hdrEncode(outputFinalColor);
    return OUT;
}

#elif defined(MFT_OutputFinalColor) && defined(MFT_ForwardShading) && !defined(MFT_MaterialDeprecated)
#include "shaders/common/lighting.hlsl"
#define HAS_FRAGOUT
struct Fragout {
   float4 target0 : SV_Target0;
};
Fragout processMaterial(Material material) {

    // Visibility
     processVisibility(material, material.vpos.xy);

    #if defined(MFT_IsTranslucent) || defined(MFT_IsTranslucentZWrite)
        if(material.opacity <= 0) {
            return (Fragout)0;
        }
    #endif

    float4 outputFinalColor = float4(0, 0, 0, material.opacity);

    // RT Lighting
    #if defined(MFT_RTLighting)
        outputFinalColor.rgb += calculateTRLightingForward(material, material.lightIds, material.positionWS);
    #else
        outputFinalColor.rgb += material.baseColor;
    #endif

    #if MFT_CubeMap
    {
        // Reflect Cube
        float3 eyeToVert = normalize( material.positionWS - eyePosWorld );
        float3 reflectVec = reflect(eyeToVert, material.normalsWS);
        uint instFlags;
        #if MFT_UseInstancing
            instFlags = getInstanceData(material.instanceId).instanceFlags;
        #else
            instFlags = instanceFlags;
        #endif
        float reflectionNorm = (instFlags & InstanceFlags_DisabledNormalizeReflection) ? 1 : saturate(hdrLuminance(ambient.rgb + 0.025) * 2);
        outputFinalColor.rgb += calculateCubeReflection(material, material.positionWS, material.instanceId, material.geomNormalWS);
    }
    #endif

    // Fog
    float fogAmount = saturate( computeSceneFog( eyePosWorld, material.positionWS, fogData.r, fogData.g, fogData.b ) );
    outputFinalColor.rgb = lerp( fogColor.rgb, outputFinalColor.rgb, fogAmount );

    // HDR Output
    Fragout OUT = (Fragout)0;
    OUT.target0 = hdrEncode(outputFinalColor);
    return OUT;
}


#elif defined(MFT_OutputVelocity)
#define HAS_FRAGOUT
struct Fragout {
   float4 target0 : SV_Target0;
};
Fragout processMaterial(Material material) {
    processVisibility(material, material.vpos.xy);
    Fragout OUT = (Fragout)0;
    OUT.target0.xy = coordsNdcToUv(perspectiveDiv(material.positionLastSS)).xy - coordsNdcToUv(perspectiveDiv(material.positionSS)).xy;
    OUT.target0.xy *= material.positionLastSS.z;
    return OUT;
}

#elif defined(MFT_AnnotationColor)
#define HAS_FRAGOUT
struct Fragout {
   float4 target0 : SV_Target0;
};
Fragout processMaterial(Material material) {
    processVisibility(material, material.vpos.xy);
    #if defined(MFT_IsTranslucent)
        if(material.opacity < 0.5) discard;
    #endif

    Fragout OUT = (Fragout)0;
    OUT.target0 = unpackColor(getInstanceData(material.instanceId).instanceColors[3]);
    OUT.target0 = float4((OUT.target0.a > 0 ? OUT.target0 : unpackColor(materialUniforms.annotationColorPacked)).rgb, 1);
    return OUT;
}

#elif defined(MFT_RadarOutput)
#include "shaders/common/gbuffer.h"
#define HAS_FRAGOUT
struct Fragout {
   float4 target0 : SV_Target0;
   float target1 : SV_Target1;
};
Fragout processMaterial(Material material) {
    Fragout OUT = (Fragout)0;
    processVisibility(material, material.vpos.xy);
    float velWsToCamera = dot(material.positionWS - material.positionLastWS, normalize(diffuseEyePosWorld - material.positionWS)) / deltaSimTimeSeconds;
    float4 normal_depth;
    float4 out_spec_none;
    encodeGBuffer(material.normalsWS, material.roughness, material.specColor, material.opacity, normal_depth, out_spec_none);
    normal_depth.a = material.opacity;
    out_spec_none.a = material.opacity;
    OUT.target0 = normal_depth;
    OUT.target1 = velWsToCamera;
    return OUT;
}

#elif !defined(HAS_FRAGOUT)
#define HAS_FRAGOUT
struct Fragout {
   float4 target0 : SV_Target0;
};
Fragout processMaterial(Material material) {
    Fragout OUT = (Fragout)0;
    processVisibility(material, material.vpos.xy);
    return OUT;
}

#endif

#endif // _SHADERGEN_PERMUTATION_H_HLSL_
