#include "shaders/common/postFx/passthru.h.hlsl"

PFXVertToPix main(PFXVert IN)
{
    PFXVertToPix OUT;

    OUT.hpos = float4(IN.pos, 1.0f);
    OUT.uv0 = IN.uv;
    OUT.uv1 = IN.uv;
    OUT.uv2 = IN.uv;
    OUT.uv3 = IN.uv;
    OUT.wsEyeRay = IN.wsEyeRay;
    return OUT;
}
