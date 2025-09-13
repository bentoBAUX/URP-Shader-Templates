Shader "bentoBAUX/URP Lit"
{
    Properties
    {
        _BaseColor ("Base Color", Color) = (1,1,1,1)
        _BaseMap ("Base Map", 2D) = "white" {}
        [Normal]_NormalMap ("Normal Map", 2D) = "bump" {}
        _NormalStrength ("Normal Strength", Range(0,3)) = 1
    }

    SubShader
    {
        Tags
        {
            "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline"
        }

        Pass
        {
            // The LightMode tag matches the ShaderPassName set in UniversalRenderPipeline.cs.
            // The SRPDefaultUnlit pass and passes without the LightMode tag are also rendered by URP
            Name "ForwardLit"
            Tags
            {
                "LightMode" = "UniversalForward"
            }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile_fog

            // This multi_compile declaration is required for the Forward rendering path
            #pragma multi_compile _ _ADDITIONAL_LIGHTS

            // This multi_compile declaration is required for the Forward+ rendering path
            #pragma multi_compile _ _FORWARD_PLUS

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/RealtimeLights.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/ShaderVariablesFunctions.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3x3 TBN : TEXCOORD1;
                float2 uv : TEXCOORD4;
            };

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                float4 _BaseMap_ST;
                half _NormalStrength;
            CBUFFER_END

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);
            TEXTURE2D(_NormalMap);
            SAMPLER(sampler_NormalMap);

            Varyings vert(Attributes IN)
            {
                Varyings OUT;

                // Positions
                OUT.positionWS = TransformObjectToWorld(IN.positionOS.xyz);
                OUT.positionCS = TransformWorldToHClip(OUT.positionWS);

                // Build TBN
                float3 N = normalize(TransformObjectToWorldNormal(IN.normalOS));
                float3 T = normalize(TransformObjectToWorldDir(IN.tangentOS.xyz));
                T = normalize(T - N * dot(N, T)); // Re-orthogonalize using one step of Gram-Schmidt in case of small import errors.
                float3 B = normalize(cross(N, T)) * IN.tangentOS.w;
                OUT.TBN = float3x3(T, B, N);

                // UV Transform
                OUT.uv = IN.uv * _BaseMap_ST.xy + _BaseMap_ST.zw;

                return OUT;
            }

            half3 ProcessNormals(Varyings IN)
            {
                // Tangent-space normal from normal map
                half3 nTS = UnpackNormal(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, IN.uv));
                nTS.xy *= _NormalStrength;

                // IN.TBN is world->tangent, so transpose(TBN) = tangent->world
                return normalize(mul(transpose(IN.TBN), nTS));
            }

            // https://discussions.unity.com/t/how-to-compute-fog-in-hlsl-on-urp/943637/4
            void ApplyFog(inout float4 color, float3 positionWS)
            {
                #if defined(FOG_LINEAR) || defined(FOG_EXP) || defined(FOG_EXP2)
                    float viewZ = -TransformWorldToView(positionWS).z;
                    float nearZ0ToFarZ = max(viewZ - _ProjectionParams.y, 0);
                    float density = 1.0f - ComputeFogIntensity(ComputeFogFactorZ0ToFar(nearZ0ToFarZ));

                    color = lerp(color, unity_FogColor,  density);
                #else
                color = color;
                #endif
            }

            float3 Lambert(float3 normalWS, Light light)
            {
                float NdotL = dot(normalWS, normalize(light.direction));
                return saturate(NdotL) * light.color * light.distanceAttenuation * light.shadowAttenuation;
            }

            // This function loops through the lights in the scene
            float3 LightLoop(float4 color, InputData inputData)
            {
                float3 lighting = 0;

                // Get the main light
                Light mainLight = GetMainLight();
                lighting += SampleSH(inputData.normalWS) + Lambert(inputData.normalWS, mainLight);

                // Get additional lights
                #if defined(_ADDITIONAL_LIGHTS)

                // Additional light loop for non-main directional lights. This block is specific to Forward+.
                #if USE_FORWARD_PLUS
                UNITY_LOOP for (uint lightIndex = 0; lightIndex < min(URP_FP_DIRECTIONAL_LIGHTS_COUNT, MAX_VISIBLE_LIGHTS); lightIndex++)
                {
                    Light additionalLight = GetAdditionalLight(lightIndex, inputData.positionWS, half4(1,1,1,1));
                    lighting += Lambert(inputData.normalWS, additionalLight);
                }
                #endif

                // Additional light loop.
                uint pixelLightCount = GetAdditionalLightsCount();
                LIGHT_LOOP_BEGIN(pixelLightCount)
                    Light additionalLight = GetAdditionalLight(lightIndex, inputData.positionWS, half4(1,1,1,1));
                    lighting += Lambert(inputData.normalWS, additionalLight);
                LIGHT_LOOP_END

                #endif

                return color * lighting;
            }

            half4 frag(Varyings IN) : SV_Target0
            {
                // The Forward+ light loop (LIGHT_LOOP_BEGIN) requires the InputData struct to be in its scope.
                InputData inputData = (InputData)0;
                inputData.positionWS = IN.positionWS;
                inputData.normalWS = ProcessNormals(IN);
                inputData.viewDirectionWS = GetWorldSpaceNormalizeViewDir(IN.positionWS);
                inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(IN.positionCS);

                // Material Input Setup
                float4 surfaceColor = _BaseColor * SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv);
                float alpha = surfaceColor.a * _BaseColor.a;

                // Calculate Lighting
                float3 lighting = LightLoop(surfaceColor, inputData);

                float4 finalColor = float4(lighting, alpha);

                ApplyFog(finalColor, IN.positionWS);

                return finalColor;
            }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags
            {
                "LightMode" = "ShadowCaster"
            }

            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull Off

            HLSLPROGRAM
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment
            #pragma target 2.0

            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"
            ENDHLSL
        }

    }
}