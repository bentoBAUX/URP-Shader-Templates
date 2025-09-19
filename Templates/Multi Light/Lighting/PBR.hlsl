#ifndef PBR_INCLUDED
#define PBR_INCLUDED

float G_SchlickGGX(float NoX, float a)
{
    float k = (a + 1.0);
    k = (k * k) * 0.125;
    return NoX / (NoX * (1.0 - k) + k);
}

float G_Smith(float a, float NoV, float NoL)
{
    float gv = G_SchlickGGX(NoV, a);
    float gl = G_SchlickGGX(NoL, a);
    return gv * gl;
}

float DistributionGGX(float3 N, float3 H, float roughness)
{
    float a = roughness * roughness;
    float a2 = a * a;
    float NdotH = max(dot(N, H), 0.0);
    float NdotH2 = NdotH * NdotH;

    float num = a2;
    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    denom = PI * denom * denom;

    return num / denom;
}

float GeometrySchlickGGX(float NdotV, float roughness)
{
    float r = (roughness + 1.0);
    float k = (r * r) / 8.0;

    float num = NdotV;
    float denom = NdotV * (1.0 - k) + k;

    return num / denom;
}

float GeometrySmith(float3 N, float3 V, float3 L, float roughness)
{
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    float ggx2 = GeometrySchlickGGX(NdotV, roughness);
    float ggx1 = GeometrySchlickGGX(NdotL, roughness);

    return ggx1 * ggx2;
}

float3 fresnelSchlick(float cosTheta, float3 F0)
{
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

// https://learnopengl.com/PBR/Lighting
float3 PBR(Surf surfaceData, Light lightData)
{
    float3 c = surfaceData.baseColor.rgb;
    float3 n = normalize(surfaceData.normalWS);
    float3 v = normalize(surfaceData.viewDirectionWS);
    float3 l = normalize(lightData.direction);
    float3 h = normalize(v + l);
    float3 radiance = lightData.color.rgb * lightData.distanceAttenuation * lightData.shadowAttenuation;
    float roughness = max(surfaceData.roughness, 0.02);
    float metallic = surfaceData.metallic;

    float3 F0 = lerp(0.04, c, metallic);

    float NDF = DistributionGGX(n, h, roughness);
    float G = GeometrySmith(n, v, l, roughness);
    float3 F = fresnelSchlick(max(dot(h, v), 0.0), F0);

    float3 kS = F;
    float3 kD = float3(1, 1, 1) - kS;
    kD *= 1.0 - metallic;

    float3 numerator = NDF * G * F;
    float denominator = 4.0 * max(dot(n, v), 0.0) * max(dot(n, l), 0.0) + 0.0001;
    float3 specular = numerator / denominator;

    // add to outgoing radiance Lo
    float NdotL = max(dot(n, l), 0.0);
    float3 Lo = (kD * c / PI + specular) * radiance * NdotL;

    return Lo;
}


#endif
