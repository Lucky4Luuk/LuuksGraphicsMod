#ifndef _MATERIAL_PERMUTATION_H_HLSL_
#define _MATERIAL_PERMUTATION_H_HLSL_

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
    float3 materiaSpecularColor = saturate(material.specColor);
    float4 normal_depth;
    float4 out_spec_none;
    encodeGBuffer(material.normalsWS, material.roughness, materiaSpecularColor.rgb, material.opacity, normal_depth, out_spec_none);
    normal_depth.a = material.opacity;
    out_spec_none.a = material.opacity;
    OUT.target0 = normal_depth;
#if MFT_RTLighting1_5
    OUT.target1 = out_spec_none;
#endif
    return OUT;
}
#endif

#endif //_MATERIAL_PERMUTATION_H_HLSL_
