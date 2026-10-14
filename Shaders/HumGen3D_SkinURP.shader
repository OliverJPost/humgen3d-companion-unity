// Skin for the Universal Render Pipeline.
// URP/Lit has no subsurface scattering: light that enters skin comes out again around where it
// went in, which softens the shading and turns the edge of the light and of a shadow red. Lit
// gives skin a hard, grey terminator, and its default reflectance with smoothness from the map
// makes it look oiled. This shader keeps the cost of Lit and approximates both the way games
// usually do without a screen-space pass:
// - Diffuse: the light wraps further around the surface the deeper a color scatters (red
//   most), and the detail of the normal map is blurred per color, so pores and wrinkles stay
//   sharp in blue and soften in red. Shadow edges get the same red fringe.
// - Specular: two GGX lobes at skin reflectance (0.028), a sharp one for the oily top layer and
//   a broad one for the rough skin under it, and a split-sum environment term that keeps the
//   reflection of the sky from turning the edges of the face into a wet rim.
// It has the property set of URP/Lit (base, normal, metallic-smoothness, occlusion map), so a
// material can be switched to Lit and back without losing its textures, and keeps every
// property in UnityPerMaterial, so it is SRP Batcher compatible.
Shader "Human Generator 3D/Skin URP"
{
    Properties
    {
        // The property names of URP/Lit
        _WorkflowMode("WorkflowMode", Float) = 1.0

        [MainTexture] _BaseMap("Albedo", 2D) = "white" {}
        [MainColor] _BaseColor("Color", Color) = (1,1,1,1)

        _Cutoff("Alpha Cutoff", Range(0.0, 1.0)) = 0.5

        // Multiplies the smoothness from the alpha of the metallic-smoothness map
        _Smoothness("Smoothness", Range(0.0, 1.0)) = 1.0
        _SmoothnessTextureChannel("Smoothness texture channel", Float) = 0
        // Skin is not metallic: only the alpha (smoothness) of this map is read
        _Metallic("Metallic", Range(0.0, 1.0)) = 0.0
        _MetallicGlossMap("Metallic", 2D) = "white" {}

        [ToggleOff] _SpecularHighlights("Specular Highlights", Float) = 1.0
        [ToggleOff] _EnvironmentReflections("Environment Reflections", Float) = 1.0

        _BumpScale("Scale", Float) = 1.0
        _BumpMap("Normal Map", 2D) = "bump" {}

        _OcclusionStrength("Strength", Range(0.0, 1.0)) = 1.0
        _OcclusionMap("Occlusion", 2D) = "white" {}

        [Header(Skin)]
        // How far each color of the light travels under the skin, relative to red
        _SubsurfaceColor("Subsurface Color", Color) = (1.0, 0.55, 0.4, 1)
        // How far the light wraps around the surface past the shadow line, for red
        _ScatterWidth("Scatter Width", Range(0.0, 1.0)) = 0.4
        // How much of the normal map the red light ignores (green and blue less)
        _NormalBlur("Normal Blur", Range(0.0, 1.0)) = 0.6
        // Reflectance at normal incidence: 0.028 is skin (IOR 1.4), Lit uses 0.04
        _SkinReflectance("Reflectance", Range(0.0, 0.08)) = 0.028
        // The two specular lobes: roughness multipliers and the share of the sharp one
        _LobeSharp("Sharp Lobe Roughness", Range(0.3, 1.0)) = 0.75
        _LobeBroad("Broad Lobe Roughness", Range(1.0, 2.0)) = 1.3
        _LobeMix("Sharp Lobe Share", Range(0.0, 1.0)) = 0.85

        // Blending state of Lit, opaque by default
        _Surface("__surface", Float) = 0.0
        _Blend("__blend", Float) = 0.0
        _Cull("__cull", Float) = 2.0
        [ToggleUI] _AlphaClip("__clip", Float) = 0.0
        [HideInInspector] _BlendOp("__blendop", Float) = 0.0
        [HideInInspector] _SrcBlend("__src", Float) = 1.0
        [HideInInspector] _DstBlend("__dst", Float) = 0.0
        [HideInInspector] _SrcBlendAlpha("__srcA", Float) = 1.0
        [HideInInspector] _DstBlendAlpha("__dstA", Float) = 0.0
        [HideInInspector] _ZWrite("__zw", Float) = 1.0
        [HideInInspector] _BlendModePreserveSpecular("_BlendModePreserveSpecular", Float) = 1.0
        [HideInInspector] _AlphaToMask("__alphaToMask", Float) = 0.0
        [HideInInspector] _AddPrecomputedVelocity("_AddPrecomputedVelocity", Float) = 0.0
        [HideInInspector] _XRMotionVectorsPass("_XRMotionVectorsPass", Float) = 1.0

        [ToggleUI] _ReceiveShadows("Receive Shadows", Float) = 1.0
        _QueueOffset("Queue offset", Float) = 0.0

        // Legacy names of the Lit inspector
        [HideInInspector] _MainTex("BaseMap", 2D) = "white" {}
        [HideInInspector] _Color("Base Color", Color) = (1, 1, 1, 1)
        [HideInInspector] _GlossMapScale("Smoothness", Float) = 0.0
        [HideInInspector] _Glossiness("Smoothness", Float) = 0.0
        [HideInInspector] _GlossyReflections("EnvironmentReflections", Float) = 0.0

        [HideInInspector][NoScaleOffset] unity_Lightmaps("unity_Lightmaps", 2DArray) = "" {}
        [HideInInspector][NoScaleOffset] unity_LightmapsInd("unity_LightmapsInd", 2DArray) = "" {}
        [HideInInspector][NoScaleOffset] unity_ShadowMasks("unity_ShadowMasks", 2DArray) = "" {}
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
            "UniversalMaterialType" = "Lit"
            "IgnoreProjector" = "True"
        }
        LOD 300

        HLSLINCLUDE
        // The inputs of every pass: one UnityPerMaterial buffer with the same layout in all of
        // them, which is what the SRP Batcher needs. SurfaceInput.hlsl declares the base and
        // normal maps and the sampling helpers the passes of URP use.
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/SurfaceInput.hlsl"

        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half4 _BaseColor;
            half _Cutoff;
            half _Smoothness;
            half _Metallic;
            half _BumpScale;
            half _OcclusionStrength;
            half4 _SubsurfaceColor;
            half _ScatterWidth;
            half _NormalBlur;
            half _SkinReflectance;
            half _LobeSharp;
            half _LobeBroad;
            half _LobeMix;
            half _Surface;
        CBUFFER_END

        TEXTURE2D(_MetallicGlossMap);   SAMPLER(sampler_MetallicGlossMap);
        TEXTURE2D(_OcclusionMap);       SAMPLER(sampler_OcclusionMap);
        ENDHLSL

        Pass
        {
            // Forward only: the skin lighting has no GBuffer layout, so the skin renders
            // forward in the Deferred path too, like the other forward-only materials
            Name "ForwardLit"
            Tags
            {
                "LightMode" = "UniversalForwardOnly"
            }

            Blend[_SrcBlend][_DstBlend], [_SrcBlendAlpha][_DstBlendAlpha]
            ZWrite[_ZWrite]
            Cull[_Cull]
            AlphaToMask[_AlphaToMask]

            HLSLPROGRAM
            #pragma target 3.0

            #pragma vertex SkinPassVertex
            #pragma fragment SkinPassFragment

            // Material keywords, those of Lit that the inputs read
            #pragma shader_feature_local _NORMALMAP
            #pragma shader_feature_local _RECEIVE_SHADOWS_OFF
            #pragma shader_feature_local_fragment _ALPHATEST_ON
            #pragma shader_feature_local_fragment _METALLICSPECGLOSSMAP
            #pragma shader_feature_local_fragment _OCCLUSIONMAP
            #pragma shader_feature_local_fragment _SPECULARHIGHLIGHTS_OFF
            #pragma shader_feature_local_fragment _ENVIRONMENTREFLECTIONS_OFF

            // Universal Pipeline keywords, those of URP 14 to 17; a keyword a version
            // doesn't know is a plain unset define
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile _ EVALUATE_SH_MIXED EVALUATE_SH_VERTEX
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BLENDING
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BOX_PROJECTION
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile_fragment _ _SCREEN_SPACE_OCCLUSION
            #pragma multi_compile_fragment _ _LIGHT_COOKIES
            #pragma multi_compile _ _LIGHT_LAYERS
            #pragma multi_compile _ _FORWARD_PLUS
            #pragma multi_compile _ _CLUSTER_LIGHT_LOOP

            // Unity defined keywords
            #pragma multi_compile _ LIGHTMAP_SHADOW_MIXING
            #pragma multi_compile _ SHADOWS_SHADOWMASK
            #pragma multi_compile _ DIRLIGHTMAP_COMBINED
            #pragma multi_compile _ LIGHTMAP_ON
            #pragma multi_compile _ LOD_FADE_CROSSFADE
            #pragma multi_compile_fog

            #pragma multi_compile_instancing
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DOTS.hlsl"

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #if defined(LOD_FADE_CROSSFADE)
                #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/LODCrossFade.hlsl"
            #endif

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
                float2 texcoord : TEXCOORD0;
                float2 staticLightmapUV : TEXCOORD1;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                half3 normalWS : TEXCOORD2;
                half4 tangentWS : TEXCOORD3; // w is the sign of the bitangent
                half4 fogFactorAndVertexLight : TEXCOORD4;
#if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
                float4 shadowCoord : TEXCOORD5;
#endif
                DECLARE_LIGHTMAP_OR_SH(staticLightmapUV, vertexSH, 6);
                float4 positionCS : SV_POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings SkinPassVertex(Attributes input)
            {
                Varyings output = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);
                output.uv = TRANSFORM_TEX(input.texcoord, _BaseMap);
                output.positionWS = vertexInput.positionWS;
                output.positionCS = vertexInput.positionCS;
                output.normalWS = normalInput.normalWS;
                real sign = input.tangentOS.w * GetOddNegativeScale();
                output.tangentWS = half4(normalInput.tangentWS.xyz, sign);
                half3 vertexLight = VertexLighting(vertexInput.positionWS, normalInput.normalWS);
                output.fogFactorAndVertexLight = half4(ComputeFogFactor(vertexInput.positionCS.z), vertexLight);
                OUTPUT_LIGHTMAP_UV(input.staticLightmapUV, unity_LightmapST, output.staticLightmapUV);
                OUTPUT_SH(output.normalWS.xyz, output.vertexSH);
#if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
                output.shadowCoord = GetShadowCoord(vertexInput);
#endif
                return output;
            }

            struct SkinSurface
            {
                half3 albedo;
                half3 normalWS;       // with the normal map, for the specular
                half3 vertexNormalWS; // without it
                half3 viewDirWS;
                half roughness;       // perceptual roughness
                half reflectance;
            };

            // The light per color after it scattered under the skin. Each color takes the
            // detail of the normal map less into account the further it travels (the normal
            // blur), and wraps further past the line where the surface turns from the light.
            half3 SkinDiffuse(half3 normalWS, half3 vertexNormalWS, half3 lightDir)
            {
                half detailed = dot(normalWS, lightDir);
                half smooth = dot(vertexNormalWS, lightDir);
                half3 NdotL = lerp(detailed.xxx, smooth.xxx, _NormalBlur * _SubsurfaceColor.rgb);
                half3 wrap = _ScatterWidth * _SubsurfaceColor.rgb;
                // Raised to 1 + wrap, so the lit side keeps the brightness and hue of Lambert
                // and only the tail past the shadow line is lifted, most in red
                return PositivePow(saturate((NdotL + wrap) / (1.0h + wrap)), 1.0h + wrap);
            }

            // The shadow edge gets the same red fringe: light that reached the skin just
            // outside the shadow comes out again inside it
            half3 SkinShadow(half shadow)
            {
                half3 width = _ScatterWidth * _SubsurfaceColor.rgb;
                return saturate(shadow + width * (shadow - shadow * shadow));
            }

            // URP's GGX lobe (Lighting.hlsl, DirectBRDFSpecular) for one roughness
            half SpecularLobe(half NdotH, half LdotH2, half roughness)
            {
                half roughness2 = max(roughness * roughness, HALF_MIN);
                half d = NdotH * NdotH * (roughness2 - 1.0h) + 1.00001h;
                half specular = roughness2 / ((d * d) * max(0.1h, LdotH2) * (roughness * 4.0h + 2.0h));
#if REAL_IS_HALF
                specular = clamp(specular - HALF_MIN, 0.0h, 1000.0h);
#endif
                return specular;
            }

            half3 SkinLighting(Light light, SkinSurface s)
            {
                half3 lightDir = light.direction;
                half3 radiance = light.color * light.distanceAttenuation;
                half3 color = s.albedo * SkinDiffuse(s.normalWS, s.vertexNormalWS, lightDir) * SkinShadow(light.shadowAttenuation);
#if !defined(_SPECULARHIGHLIGHTS_OFF)
                half NdotL = saturate(dot(s.normalWS, lightDir));
                float3 halfDir = SafeNormalize(float3(lightDir) + float3(s.viewDirWS));
                half NdotH = half(saturate(dot(s.normalWS, halfDir)));
                half LdotH = half(saturate(dot(lightDir, halfDir)));
                half roughness = max(PerceptualRoughnessToRoughness(s.roughness), HALF_MIN_SQRT);
                half specular = lerp(
                    SpecularLobe(NdotH, LdotH * LdotH, min(roughness * _LobeBroad, 1.0h)),
                    SpecularLobe(NdotH, LdotH * LdotH, roughness * _LobeSharp),
                    _LobeMix);
                color += s.reflectance * specular * NdotL * light.shadowAttenuation;
#endif
                return color * radiance;
            }

            // The split-sum environment term of a dielectric (Karis' analytic fit): how much
            // of the environment reflects at this view angle and roughness
            half EnvironmentReflectance(half reflectance, half perceptualRoughness, half NdotV)
            {
                const half4 c0 = half4(-1.0h, -0.0275h, -0.572h, 0.022h);
                const half4 c1 = half4(1.0h, 0.0425h, 1.04h, -0.04h);
                half4 r = perceptualRoughness * c0 + c1;
                half a004 = min(r.x * r.x, exp2(-9.28h * NdotV)) * r.x + r.y;
                half2 ab = half2(-1.04h, 1.04h) * a004 + r.zw;
                return reflectance * ab.x + ab.y;
            }

            void SkinPassFragment(Varyings input, out half4 outColor : SV_Target0)
            {
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                half4 albedoAlpha = SampleAlbedoAlpha(input.uv, TEXTURE2D_ARGS(_BaseMap, sampler_BaseMap));
                half alpha = Alpha(albedoAlpha.a, _BaseColor, _Cutoff);
#if defined(LOD_FADE_CROSSFADE)
                LODFadeCrossFade(input.positionCS);
#endif

                SkinSurface s;
                s.albedo = albedoAlpha.rgb * _BaseColor.rgb;
#if defined(_METALLICSPECGLOSSMAP)
                half smoothness = SAMPLE_TEXTURE2D(_MetallicGlossMap, sampler_MetallicGlossMap, input.uv).a * _Smoothness;
#else
                half smoothness = _Smoothness;
#endif
                s.roughness = PerceptualSmoothnessToPerceptualRoughness(smoothness);
                s.reflectance = _SkinReflectance;
#if defined(_OCCLUSIONMAP)
                half occlusion = LerpWhiteTo(SAMPLE_TEXTURE2D(_OcclusionMap, sampler_OcclusionMap, input.uv).g, _OcclusionStrength);
#else
                half occlusion = 1.0h;
#endif

                s.vertexNormalWS = NormalizeNormalPerPixel(input.normalWS);
#if defined(_NORMALMAP)
                half3 normalTS = SampleNormal(input.uv, TEXTURE2D_ARGS(_BumpMap, sampler_BumpMap), _BumpScale);
                half3 bitangentWS = input.tangentWS.w * cross(input.normalWS, input.tangentWS.xyz);
                half3x3 tangentToWorld = half3x3(input.tangentWS.xyz, bitangentWS, input.normalWS);
                s.normalWS = NormalizeNormalPerPixel(TransformTangentToWorld(normalTS, tangentToWorld));
#else
                s.normalWS = s.vertexNormalWS;
#endif
                s.viewDirWS = GetWorldSpaceNormalizeViewDir(input.positionWS);

                InputData inputData = (InputData)0;
                inputData.positionWS = input.positionWS;
                inputData.normalWS = s.normalWS;
                inputData.viewDirectionWS = s.viewDirWS;
#if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
                inputData.shadowCoord = input.shadowCoord;
#elif defined(MAIN_LIGHT_CALCULATE_SHADOWS)
                inputData.shadowCoord = TransformWorldToShadowCoord(inputData.positionWS);
#else
                inputData.shadowCoord = float4(0, 0, 0, 0);
#endif
                inputData.fogCoord = input.fogFactorAndVertexLight.x;
                inputData.vertexLighting = input.fogFactorAndVertexLight.yzw;
                inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(input.positionCS);
                inputData.shadowMask = SAMPLE_SHADOWMASK(input.staticLightmapUV);
                // The ambient light scatters too: sampled with the normal of the mesh, so the
                // normal map does not darken the skin in the shade
                inputData.bakedGI = SAMPLE_GI(input.staticLightmapUV, input.vertexSH, s.vertexNormalWS);

                half4 shadowMask = CalculateShadowMask(inputData);
                AmbientOcclusionFactor aoFactor = CreateAmbientOcclusionFactor(inputData.normalizedScreenSpaceUV, occlusion);
                Light mainLight = GetMainLight(inputData, shadowMask, aoFactor);
                MixRealtimeAndBakedGI(mainLight, s.vertexNormalWS, inputData.bakedGI);

                // Ambient: the diffuse, and the environment reflected at skin reflectance
                half NdotV = saturate(dot(s.normalWS, s.viewDirWS));
                half3 color = inputData.bakedGI * s.albedo * aoFactor.indirectAmbientOcclusion;
                half3 reflectVector = reflect(-s.viewDirWS, s.normalWS);
                half3 environment = GlossyEnvironmentReflection(reflectVector, inputData.positionWS, s.roughness, aoFactor.indirectAmbientOcclusion, inputData.normalizedScreenSpaceUV);
                color += environment * EnvironmentReflectance(s.reflectance, s.roughness, NdotV);

                color += SkinLighting(mainLight, s);

#if defined(_ADDITIONAL_LIGHTS)
                uint pixelLightCount = GetAdditionalLightsCount();
#if USE_FORWARD_PLUS || USE_CLUSTER_LIGHT_LOOP
                for (uint lightIndex = 0; lightIndex < min(URP_FP_DIRECTIONAL_LIGHTS_COUNT, MAX_VISIBLE_LIGHTS); lightIndex++)
                {
                    Light light = GetAdditionalLight(lightIndex, inputData, shadowMask, aoFactor);
#ifdef _LIGHT_LAYERS
                    if (IsMatchingLightLayer(light.layerMask, GetMeshRenderingLayer()))
#endif
                        color += SkinLighting(light, s);
                }
#endif
                LIGHT_LOOP_BEGIN(pixelLightCount)
                    Light light = GetAdditionalLight(lightIndex, inputData, shadowMask, aoFactor);
#ifdef _LIGHT_LAYERS
                    if (IsMatchingLightLayer(light.layerMask, GetMeshRenderingLayer()))
#endif
                        color += SkinLighting(light, s);
                LIGHT_LOOP_END
#endif
#if defined(_ADDITIONAL_LIGHTS_VERTEX)
                color += inputData.vertexLighting * s.albedo;
#endif

                color = MixFog(color, inputData.fogCoord);
                outColor = half4(color, alpha);
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
            Cull[_Cull]

            HLSLPROGRAM
            #pragma target 2.0

            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment

            #pragma shader_feature_local _ALPHATEST_ON

            #pragma multi_compile_instancing
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DOTS.hlsl"

            #pragma multi_compile _ LOD_FADE_CROSSFADE
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

            #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags
            {
                "LightMode" = "DepthOnly"
            }

            ZWrite On
            ColorMask R
            Cull[_Cull]

            HLSLPROGRAM
            #pragma target 2.0

            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment

            #pragma shader_feature_local _ALPHATEST_ON

            #pragma multi_compile _ LOD_FADE_CROSSFADE

            #pragma multi_compile_instancing
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DOTS.hlsl"

            #include "Packages/com.unity.render-pipelines.universal/Shaders/DepthOnlyPass.hlsl"
            ENDHLSL
        }

        Pass
        {
            // Depth and normals of a forward-only material, for ambient occlusion and decals
            Name "DepthNormalsOnly"
            Tags
            {
                "LightMode" = "DepthNormalsOnly"
            }

            ZWrite On
            Cull[_Cull]

            HLSLPROGRAM
            #pragma target 2.0

            #pragma vertex DepthNormalsVertex
            #pragma fragment DepthNormalsFragment

            #pragma shader_feature_local _ALPHATEST_ON

            #pragma multi_compile_fragment _ _GBUFFER_NORMALS_OCT
            #pragma multi_compile _ LOD_FADE_CROSSFADE

            #pragma multi_compile_instancing
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DOTS.hlsl"

            #include "Packages/com.unity.render-pipelines.universal/Shaders/DepthNormalsPass.hlsl"
            ENDHLSL
        }
    }

    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}
