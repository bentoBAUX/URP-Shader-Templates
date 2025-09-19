#ifndef LAMBERT_INCLUDED
#define LAMBERT_INCLUDED

float3 Lambert(float3 normalWS, Light light)
{
    float NdotL = dot(normalWS, normalize(light.direction));
    return saturate(NdotL) * light.color * light.distanceAttenuation * light.shadowAttenuation;
}

#endif