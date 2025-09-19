Shader "bentoBAUX/Multi-light"
{
    Properties
    {
        _BaseColor ("Base Color", Color) = (1,1,1,1)
        _BaseMap ("Base Map", 2D) = "white" {}
        [Normal]_NormalMap ("Normal Map", 2D) = "bump" {}
        _NormalStrength ("Normal Strength", Float) = 1

        [Enum(Lambert,0, BlinnPhong,1, PBR,2)]
        _LightingModel("Lighting Model", Float) = 0

        // Blinn Phong
        _k("K Factors", Vector) = (0.25,0.5,0.25)
        _SpecularExponent("Shininess", Range(1,128)) = 32

        // PBR
        _Roughness("Roughness", Range(0.02,1)) = 0.5
        [Toggle(_USE_ROUGHNESS_MAP)] _UseRoughnessMap("Use Roughness Map", Float) = 0
        _RoughnessMap("Roughness Map", 2D) = "white" {}

        _Metallic("Metallic", Range(0,1)) = 0.5
        [Toggle(_USE_METALLIC_MAP)] _UseMetallicMap("Use Metallic Map", Float) = 0
        _MetallicMap("Metallic Map", 2D) = "white"{}

        _AOMap("Ambient Occlusion Map", 2D) = "white" {}
        _AOStrength("AO Strength", Float) = 1
        [Toggle(_USE_TONEMAPPING)] _UseToneMapping("Tone Map (Gamma Correction)", Float) = 1
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

            #pragma shader_feature_local _LM_LAMBERT _LM_BLINNPHONG _LM_PBR

            #pragma shader_feature_local _USE_ROUGHNESS_MAP
            #pragma shader_feature_local _USE_METALLIC_MAP
            #pragma shader_feature_local _USE_TONEMAPPING

            #pragma shader_feature_local _SSS_ON

            #pragma multi_compile_fog

            // This multi_compile declaration is required for the Forward rendering path
            #pragma multi_compile _ _ADDITIONAL_LIGHTS

            // This multi_compile declaration is required for the Forward+ rendering path
            #pragma multi_compile _ _FORWARD_PLUS

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/RealtimeLights.hlsl"

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

            struct Surf
            {
                float4 baseColor;
                float alpha;
                float3 normalWS;
                float3 viewDirectionWS;
                float2 uv;
                float thickness;
                float roughness;
                float metallic;
                float ao;
            };

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                float4 _BaseMap_ST;
                half _NormalStrength;

                float3 _k;
                float _SpecularExponent;

                float _Roughness;
                float _Metallic;
                float _AOStrength;
            CBUFFER_END

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            TEXTURE2D(_NormalMap);
            SAMPLER(sampler_NormalMap);

            TEXTURE2D(_RoughnessMap);
            SAMPLER(sampler_RoughnessMap);

            TEXTURE2D(_MetallicMap);
            SAMPLER(sampler_MetallicMap);

            TEXTURE2D(_AOMap);
            SAMPLER(sampler_AOMap);

            TEXTURE2D(_ThicknessMap);
            SAMPLER(sampler_ThicknessMap);

            #include "Assets/Shaders/Library/Lighting/Lambert.hlsl"
            #include "Assets/Shaders/Library/Lighting/BlinnPhong.hlsl"
            #include "Assets/Shaders/Library/Lighting/PBR.hlsl"

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

            // This function loops through the lights in the scene
            float3 LightLoop(Surf surfaceData, InputData inputData)
            {
                float3 lit = 0;
                float4 c = surfaceData.baseColor;
                // Main light
                Light mainLight = GetMainLight();
                #if defined(_LM_LAMBERT)
                lit += Lambert(inputData.normalWS, mainLight);
                #elif defined(_LM_BLINNPHONG)
                    lit += BlinnPhong(surfaceData, mainLight);
                #elif defined(_LM_PBR)
                    lit += PBR(surfaceData, mainLight);
                #endif

                #ifdef _SSS_ON
                    lit += c * mainLight.color * QuickSSS(surfaceData, mainLight); // Add SSS influence
                #endif

                #if defined(_ADDITIONAL_LIGHTS)
                #if USE_FORWARD_PLUS
                UNITY_LOOP for (uint i = 0; i < min(URP_FP_DIRECTIONAL_LIGHTS_COUNT, MAX_VISIBLE_LIGHTS); i++)
                {
                    Light addL = GetAdditionalLight(i, inputData.positionWS, half4(1,1,1,1));
                #if defined(_LM_LAMBERT)
                    lit += Lambert(inputData.normalWS, addL);
                #elif defined(_LM_BLINNPHONG)
                    lit += BlinnPhong(surfaceData, addL);
                #elif defined(_LM_PBR)
                    lit += PBR(surfaceData, addL);
                #endif

                }
                #endif

                uint count = GetAdditionalLightsCount();
                LIGHT_LOOP_BEGIN(count)
                    Light addL = GetAdditionalLight(lightIndex, inputData.positionWS, half4(1,1,1,1));
                #if defined(_LM_LAMBERT)
                    lit += Lambert(inputData.normalWS, addL);
                #elif defined(_LM_BLINNPHONG)
                    lit += BlinnPhong(surfaceData, addL);
                #elif defined(_LM_PBR)
                    lit += PBR(surfaceData, addL);
                #endif
                LIGHT_LOOP_END
                #endif

                // Ambient is only added once
                #if defined(_LM_BLINNPHONG)
                half3 ambient = _k.x * c * SampleSH(surfaceData.normalWS);
                lit += ambient;
                #elif defined(_LM_PBR)
                float3 ambient = 0.03 * c * surfaceData.ao * SampleSH(surfaceData.normalWS);
                lit += ambient;
                #endif

                return lit;
            }

            half4 frag(Varyings IN) : SV_Target0
            {
                // The Forward+ light loop (LIGHT_LOOP_BEGIN) requires the InputData struct to be in its scope.
                InputData inputData = (InputData)0;
                inputData.positionWS = IN.positionWS;
                inputData.normalWS = ProcessNormals(IN);
                inputData.viewDirectionWS = GetWorldSpaceNormalizeViewDir(IN.positionWS);
                inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(IN.positionCS);

                // Surface data setup
                Surf surfaceData = (Surf)0;
                surfaceData.baseColor = _BaseColor * SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv);
                surfaceData.alpha = surfaceData.baseColor.a * _BaseColor.a;
                surfaceData.normalWS = inputData.normalWS;
                surfaceData.viewDirectionWS = inputData.viewDirectionWS;
                surfaceData.uv = IN.uv;
                surfaceData.thickness = SAMPLE_TEXTURE2D(_ThicknessMap, sampler_ThicknessMap, IN.uv).r;

                #ifdef _USE_ROUGHNESS_MAP
                surfaceData.roughness = SAMPLE_TEXTURE2D(_RoughnessMap, sampler_RoughnessMap, IN.uv).r;
                #else
                surfaceData.roughness = _Roughness;
                #endif

                #ifdef _USE_METALLIC_MAP
                surfaceData.metallic = SAMPLE_TEXTURE2D(_MetallicMap, sampler_MetallicMap, IN.uv).r;
                #else
                surfaceData.metallic = _Metallic;
                #endif

                surfaceData.ao = SAMPLE_TEXTURE2D(_AOMap, sampler_AOMap, IN.uv).r * _AOStrength;

                // Calculate Lighting
                float3 lighting = LightLoop(surfaceData, inputData);

                float4 finalColor = float4(lighting, surfaceData.alpha);

                ApplyFog(finalColor, IN.positionWS);

                #ifdef _USE_TONEMAPPING
                finalColor = finalColor / (finalColor + 1);
                finalColor = pow(finalColor, 1/2.2);
                #endif

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
    CustomEditor "bentoBAUX.MultiLightGUI"
}