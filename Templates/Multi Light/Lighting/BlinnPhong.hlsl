#ifndef BLINN_PHONG_INCLUDED
#define BLINN_PHONG_INCLUDED

// Blinn-Phong lighting model
float3 BlinnPhong(Surf surfaceData, Light lightData)
{
    float4 c = surfaceData.baseColor;
    float3 n = normalize(surfaceData.normalWS);
    float3 v = normalize(surfaceData.viewDirectionWS);
    half3 l = normalize(lightData.direction);
    half3 h = normalize(l + v);

    half NdotL = saturate(dot(n, l));

    half Id = _k.y * NdotL;
    half Is = _k.z * pow(saturate(dot(h, n)), _SpecularExponent);

    float atten = lightData.distanceAttenuation * lightData.shadowAttenuation;

    half3 diffuse = Id * c * lightData.color * atten;
    half3 specular = Is * lightData.color * atten;
    return diffuse + specular;
}

#endif // BLINN_PHONG_INCLUDED