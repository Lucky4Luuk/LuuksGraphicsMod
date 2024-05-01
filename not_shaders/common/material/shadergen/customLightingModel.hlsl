#include "shaders/common/lighting.hlsl"
#include "shaders/common/lighting/shadowMap/shadowMapPSSM.h.hlsl"
#include "shaders/common/lighting.hlsl"

struct CustomFragout {
   float4 target0 : SV_Target0;
};

CustomFragout newProcessMaterial(Material material) {
    // Visibility
    processVisibility(material, material.vpos.xy);

    float4 outputFinalColor = float4(1.0, 0, 0, material.opacity);

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
