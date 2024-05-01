#ifndef _PERMUTATIONS_V0_HLSL_
#define _PERMUTATIONS_V0_HLSL_

#if !defined(MFT_MaterialDeprecated)
    #error The Shadergen material is not an old material.
#endif

#include "shaders/common/lighting.hlsl"
#include "shaders/common/lighting/shadowMap/shadowMapPSSM.h.hlsl"

TextureCube getCustomCubemap();

float3 calculateCubeReflectionV0(Material material, float3 wsPosition, uint instanceID, float3 geomNormWS) {
    float3 eyeToVert = normalize( wsPosition - eyePosWorld );
    float3 outputFinalColor = 0;

#if !defined(MFT_SceneCubeMap)
    TextureCube refMap = getCustomCubemap();
    float reflectionNorm = saturate(hdrLuminance(ambient.rgb + 0.025) * 2);
#else
    TextureCube refMap = sceneCubeSpecMap;
    float reflectionNorm = (getInstanceData(instanceID).instanceFlags & InstanceFlags_DisabledNormalizeReflection) ? 1 : saturate(hdrLuminance(ambient.rgb + 0.025) * 2);
#endif

    const float3 reflectVec = reflect(eyeToVert, material.normalsWS);
    const float horizonVis = any(geomNormWS != material.normalsWS) ? calculateIblHorizonVisibility(reflectVec, geomNormWS) : 1;
    outputFinalColor.rgb += refMap.SampleLevel( defaultSamplerCube, reflectVec, 0).rgb * material.ambientOclussion * horizonVis * reflectionNorm * material.cubemapReflectivity;
    return outputFinalColor;
}

float3 getCubemap(Material material, float3 wsPosition, uint instanceID, float3 geomNormWS) {
	#if !defined(MFT_SceneCubeMap)
		TextureCube refMap = getCustomCubemap();
	#else
		TextureCube refMap = sceneCubeSpecMap;
	#endif
    float3 eyeToVert = normalize( wsPosition - eyePosWorld );
	return refMap.Sample( defaultSamplerCube, eyeToVert).rgb;
}

float4 calculateDeferredRTLightingV0(inout Material material, float4 screenspacePos, out float d_NL_Att) {
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

    float4 outputFinalColor = 0;
    outputFinalColor.w = material.opacity;
    outputFinalColor.rgb += (material.diffColor / PI) * d_lightcolor;
    material.ambientOclussion *= (ambientOcclusionBuffer.Sample(defaultSamplerRT, uvScene).r);
#ifdef BNG_ADVANCED_LIGHTING
    outputFinalColor.rgb += (material.diffColor / PI) * calcDiffuseAmbient(getColorSH9(ambientSH9), ambient.rgb, material.normalsWS, ambient.a).rgb * material.ambientOclussion;
#else
    outputFinalColor.rgb += material.diffColor * calcDiffuseAmbient(ambient.rgb, material.normalsWS).rgb * material.ambientOclussion;
#endif

    outputFinalColor.rgb += material.specColor * d_specular;

    return outputFinalColor;
}

float3 calculateTRLightingForwardV0(Material material, uint4 inLightId, float3 wsPosition) {
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
    outputFinalColor.rgb += specular.rgb;
    return outputFinalColor.rgb;
}

void processVisibilityV0(inout Material material, float2 vPos) {
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

#if defined(MFT_AnnotationColor)
#define HAS_FRAGOUT
struct Fragout {
   float4 target0 : SV_Target0;
};
Fragout processMaterial(Material material) {
    Fragout OUT = (Fragout)0;

    processVisibilityV0(material, material.vpos.xy);
    #if defined(MFT_IsTranslucent)
        if(material.opacity < 0.5) discard;
    #endif

    #if defined(MFT_TerrainVertHeight)
        OUT.target0 = float4(material.annotationColor.rgb, 1);
    #elif defined(MFT_ImposterVert)
        OUT.target0 = float4(materialUniforms.materialAnnotation.rgb, 1);
    #else
        OUT.target0 = unpackColor(getInstanceData(material.instanceId).instanceColors[3]);
        OUT.target0 = float4((OUT.target0.a > 0 ? OUT.target0 : materialUniforms.materialAnnotation).rgb, 1);
    #endif

    if(bool(primFlags & PrimFlag_OutputColor)) {
        OUT.target0 = unpackColor(primOutputColor1);
    }
    return OUT;
}

#elif defined(MFT_OutputFinalColor) && defined(MFT_ForwardShading) && defined(MFT_MaterialDeprecated)
#include "shaders/common/lighting.hlsl"
#define HAS_FRAGOUT
struct Fragout {
   float4 target0 : SV_Target0;
};
Fragout processMaterial(Material material) {

    // Visibility
     processVisibilityV0(material, material.vpos.xy);

    #if defined(MFT_IsTranslucent) || defined(MFT_IsTranslucentZWrite)
        if(material.opacity <= 0) {
            return (Fragout)0;
        }
    #endif

    float4 outputFinalColor = float4(0, 0, 0, material.opacity);
    outputFinalColor.rgb += material.emissive;

    // RT Lighting
    #if defined(MFT_RTLighting)
        outputFinalColor.rgb += calculateTRLightingForwardV0(material, material.lightIds, material.positionWS);
    #else
        outputFinalColor.rgb += material.diffColor;
    #endif

    #if MFT_CubeMap
        outputFinalColor.rgb += calculateCubeReflectionV0(material, material.positionWS, material.instanceId, material.geomNormalWS);
    #endif

    // Fog
    float fogAmount = saturate( computeSceneFog( eyePosWorld, material.positionWS, fogData.r, fogData.g, fogData.b ) );
    outputFinalColor.rgb = lerp( fogColor.rgb, outputFinalColor.rgb, fogAmount );

    // HDR Output
    Fragout OUT = (Fragout)0;
    OUT.target0 = hdrEncode(outputFinalColor);
    return OUT;
}


#elif defined(MFT_OutputFinalColor) && !defined(MFT_ForwardShading) && defined(MFT_MaterialDeprecated)
#include "shaders/common/lighting.hlsl"
#define HAS_FRAGOUT
struct Fragout {
   float4 target0 : SV_Target0;
};
Fragout processMaterial(Material material) {
    // Visibility
     processVisibilityV0(material, material.vpos.xy);

    float4 outputFinalColor = float4(0, 0, 0, material.opacity);
    outputFinalColor.rgb += material.emissive;

    // Deferred RT Lighting
    {
        float d_NL_Att = 1;
        #if defined(MFT_RTLighting)
            outputFinalColor.rgb += calculateDeferredRTLightingV0(material, material.positionSS, d_NL_Att).rgb;
        #else
            outputFinalColor.rgb += material.diffColor;
        #endif

        #if MFT_CubeMap
            #if defined(MFT_SkyBox)
                outputFinalColor.rgb += getCubemap(material, material.positionWS, material.instanceId, material.geomNormalWS);
            #else
                outputFinalColor.rgb += calculateCubeReflectionV0(material, material.positionWS, material.instanceId, material.geomNormalWS) * ((saturate(d_NL_Att) * 0.75 + 0.25));
            #endif
        #endif
    }

    // HDR Output
    Fragout OUT = (Fragout)0;
    OUT.target0 = hdrEncode(outputFinalColor);
    return OUT;
}

#elif !defined(HAS_FRAGOUT)
    #include "../permutations.h.hlsl"
#endif

#endif
