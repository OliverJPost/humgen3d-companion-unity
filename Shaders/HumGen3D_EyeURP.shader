// Eyes for the Universal Render Pipeline.
// The game eyes of a Human Generator export are one opaque shell, the front of the cornea, with
// the eye baked onto it: the iris and pupil around the centre of the texture, the sclera around
// them, and a normal map with the cavity of the iris. URP/Lit shades that like a painted ball.
// A real eye is a glossy cornea with the iris a few millimetres behind it, so this shader, at
// the cost of Lit:
// - Refracts the view ray at the cornea (IOR 1.376) and samples the iris where that ray meets
//   it, so the iris shifts and bulges with the view angle instead of sitting on the surface.
// - Lights the iris and sclera with the normal map, but reflects the lights and the
//   environment off the smooth cornea (the mesh normal) at the reflectance of water, with a
//   sharp GGX lobe, so the glint stays a glint and does not grey out the pupil.
// - Darkens the limbus (the edge of the iris), can dilate the pupil, and wraps the diffuse a
//   little, as the sclera scatters light.
// It has the property set of URP/Lit (base, normal, metallic-smoothness, occlusion map), so a
// material can be switched to Lit and back without losing its textures, and keeps every
// property in UnityPerMaterial, so it is SRP Batcher compatible.
// The iris and pupil radii are those of the eye texture Human Generator bakes (the pupil is at
// the centre); other textures set them in the material.
Shader "Human Generator 3D/Eye URP"
{
    Properties
    {
        // The property names of URP/Lit
        _WorkflowMode("WorkflowMode", Float) = 1.0

        [MainTexture] _BaseMap("Albedo", 2D) = "white" {}
        [MainColor] _BaseColor("Color", Color) = (1,1,1,1)

        _Cutoff("Alpha Cutoff", Range(0.0, 1.0)) = 0.5

        // The cornea is wet: 0.9 is the roughness 0.1 the export gives the eyes
        _Smoothness("Smoothness", Range(0.0, 1.0)) = 0.9
        _SmoothnessTextureChannel("Smoothness texture channel", Float) = 0
        // An eye is not metallic: only the alpha (smoothness) of this map is read
        _Metallic("Metallic", Range(0.0, 1.0)) = 0.0
        _MetallicGlossMap("Metallic", 2D) = "white" {}

        [ToggleOff] _SpecularHighlights("Specular Highlights", Float) = 1.0
        [ToggleOff] _EnvironmentReflections("Environment Reflections", Float) = 1.0

        // The export bakes the cavity of the iris at half strength, as Lit would
        // glitter on it; here only the diffuse reads it
        _BumpScale("Scale", Float) = 1.5
        _BumpMap("Normal Map", 2D) = "bump" {}

        _OcclusionStrength("Strength", Range(0.0, 1.0)) = 1.0
        _OcclusionMap("Occlusion", 2D) = "white" {}

        [Header(Eye)]
        // Radius of the iris and of the pupil in the texture, from its centre, in UV units
        _IrisRadius("Iris Radius", Range(0.02, 0.3)) = 0.11
        _PupilRadius("Pupil Radius", Range(0.005, 0.15)) = 0.037
        // How far behind the cornea the iris lies, as a fraction of the iris radius
        _IrisDepth("Iris Depth", Range(0.0, 1.0)) = 0.45
        _CorneaIOR("Cornea IOR", Range(1.0, 2.0)) = 1.376
        // Pupil smaller (-1) or larger (1) than baked
        _PupilSize("Pupil Size", Range(-1.0, 1.0)) = 0.0
        // The dark ring at the edge of the iris, and its width as a fraction of the iris radius
        _LimbusDarken("Limbus Darkening", Range(0.0, 1.0)) = 0.5
        _LimbusWidth("Limbus Width", Range(0.02, 0.5)) = 0.15
        // Reflectance of the cornea at normal incidence: 0.025 is water (IOR 1.376)
        _EyeReflectance("Reflectance", Range(0.0, 0.08)) = 0.025
        // A faint, broad sheen on the fibres of the iris itself, under the cornea
        _IrisSheen("Iris Sheen", Range(0.0, 1.0)) = 0.3
        // How far the light wraps past the shadow line, per color (the sclera scatters red most)
        _SubsurfaceColor("Scatter Color", Color) = (1.0, 0.55, 0.4, 1)
        _ScatterWidth("Scatter Width", Range(0.0, 1.0)) = 0.15

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
        // Skipped in a project without URP, so the includes below do not
        // fail to compile there; the Built-in pipeline uses Standard
        PackageRequirements
        {
            "com.unity.render-pipelines.universal": "14.0"
        }
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
            float _IrisRadius;
            float _PupilRadius;
            float _IrisDepth;
            float _CorneaIOR;
            float _PupilSize;
            half _LimbusDarken;
            half _LimbusWidth;
            half _EyeReflectance;
            half _IrisSheen;
            half4 _SubsurfaceColor;
            half _ScatterWidth;
            half _Surface;
        CBUFFER_END

        TEXTURE2D(_MetallicGlossMap);   SAMPLER(sampler_MetallicGlossMap);
        TEXTURE2D(_OcclusionMap);       SAMPLER(sampler_OcclusionMap);
        ENDHLSL

        Pass
        {
            // Forward only: the eye lighting has no GBuffer layout, so the eyes render
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

            #pragma vertex EyePassVertex
            #pragma fragment EyePassFragment

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

            Varyings EyePassVertex(Attributes input)
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

            struct EyeSurface
            {
                half3 albedo;
                half3 normalWS;       // with the normal map, for the diffuse
                half3 corneaNormalWS; // the mesh normal, for the specular
                half3 viewDirWS;
                half roughness;       // perceptual roughness of the cornea
                half reflectance;
                half iris;            // 1 on the iris, 0 on the sclera
            };

            // Where the refracted view ray samples the eye texture. The pupil is at the
            // centre of the texture; inside the iris the ray is bent at the cornea and
            // followed down to the iris, the sclera is sampled where it is. The pupil
            // is then dilated by moving the texels of the iris radially.
            float2 EyeUV(float2 uv, float3 viewDirTS, out float distance, out float iris)
            {
                float2 centre = uv - 0.5;
                float r = length(centre);
                float R = _IrisRadius;
                iris = 1.0 - smoothstep(R, R * 1.12, r);
                // The cornea is smooth: refract at the mesh normal (z in tangent space)
                float3 refracted = refract(-viewDirTS, float3(0.0, 0.0, 1.0), 1.0 / _CorneaIOR);
                float2 shift = refracted.xy / max(-refracted.z, 0.2) * (_IrisDepth * R);
                centre += shift * iris;
                r = length(centre);
                // Pupil dilation: the texels between the pupil and the limbus are spread or
                // squeezed so the pupil has the wanted radius and the iris keeps its edge
                float p0 = _PupilRadius;
                float p = clamp(p0 * (1.0 + 0.5 * _PupilSize), 0.2 * p0, 0.8 * R);
                float sampled = r < p ? r * p0 / p : p0 + (r - p) * (R - p0) / max(R - p, 1e-4);
                sampled = r < R ? sampled : r;
                distance = r;
                return 0.5 + centre * (sampled / max(r, 1e-5));
            }

            // The diffuse light after the sclera scattered it: the light wraps past the
            // shadow line, most in red (the skin shader's wrap, at a smaller width)
            half3 EyeDiffuse(half3 normalWS, half3 lightDir)
            {
                half NdotL = dot(normalWS, lightDir);
                half3 wrap = _ScatterWidth * _SubsurfaceColor.rgb;
                return PositivePow(saturate((NdotL + wrap) / (1.0h + wrap)), 1.0h + wrap);
            }

            half3 EyeShadow(half shadow)
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

            half3 EyeLighting(Light light, EyeSurface s)
            {
                half3 lightDir = light.direction;
                half3 radiance = light.color * light.distanceAttenuation;
                half3 color = s.albedo * EyeDiffuse(s.normalWS, lightDir) * EyeShadow(light.shadowAttenuation);
#if !defined(_SPECULARHIGHLIGHTS_OFF)
                // Off the cornea, not the iris: the glint of a wet sphere
                half NdotL = saturate(dot(s.corneaNormalWS, lightDir));
                float3 halfDir = SafeNormalize(float3(lightDir) + float3(s.viewDirWS));
                half NdotH = half(saturate(dot(s.corneaNormalWS, halfDir)));
                half LdotH = half(saturate(dot(lightDir, halfDir)));
                half roughness = max(PerceptualRoughnessToRoughness(s.roughness), HALF_MIN_SQRT);
                color += s.reflectance * SpecularLobe(NdotH, LdotH * LdotH, roughness) * NdotL * light.shadowAttenuation;
                // The fibres of the iris catch a little light too, broad and faint
                half irisNdotL = saturate(dot(s.normalWS, lightDir));
                half irisNdotH = half(saturate(dot(s.normalWS, halfDir)));
                color += 0.02h * _IrisSheen * s.iris * SpecularLobe(irisNdotH, LdotH * LdotH, 0.2h) * irisNdotL * light.shadowAttenuation;
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

            void EyePassFragment(Varyings input, out half4 outColor : SV_Target0)
            {
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

#if defined(LOD_FADE_CROSSFADE)
                LODFadeCrossFade(input.positionCS);
#endif
                EyeSurface s;
                s.corneaNormalWS = NormalizeNormalPerPixel(input.normalWS);
                s.viewDirWS = GetWorldSpaceNormalizeViewDir(input.positionWS);
                half3 bitangentWS = input.tangentWS.w * cross(input.normalWS, input.tangentWS.xyz);
                half3x3 tangentToWorld = half3x3(input.tangentWS.xyz, bitangentWS, input.normalWS);
                float3 viewDirTS = normalize(float3(
                    dot(s.viewDirWS, input.tangentWS.xyz),
                    dot(s.viewDirWS, bitangentWS),
                    dot(s.viewDirWS, s.corneaNormalWS)));
                float distance, iris;
                float2 uv = EyeUV(input.uv, viewDirTS, distance, iris);
                s.iris = half(iris);

                half4 albedoAlpha = SampleAlbedoAlpha(uv, TEXTURE2D_ARGS(_BaseMap, sampler_BaseMap));
                half alpha = Alpha(albedoAlpha.a, _BaseColor, _Cutoff);
                s.albedo = albedoAlpha.rgb * _BaseColor.rgb;
                // The limbus: a dark ring where the iris meets the sclera
                float R = _IrisRadius;
                half ring = smoothstep(R * (1.0 - _LimbusWidth), R, distance) * (1.0 - smoothstep(R, R * (1.0 + 0.6 * _LimbusWidth), distance));
                s.albedo *= 1.0h - _LimbusDarken * ring;
#if defined(_METALLICSPECGLOSSMAP)
                half smoothness = SAMPLE_TEXTURE2D(_MetallicGlossMap, sampler_MetallicGlossMap, uv).a * _Smoothness;
#else
                half smoothness = _Smoothness;
#endif
                s.roughness = PerceptualSmoothnessToPerceptualRoughness(smoothness);
                s.reflectance = _EyeReflectance;
#if defined(_OCCLUSIONMAP)
                half occlusion = LerpWhiteTo(SAMPLE_TEXTURE2D(_OcclusionMap, sampler_OcclusionMap, uv).g, _OcclusionStrength);
#else
                half occlusion = 1.0h;
#endif
#if defined(_NORMALMAP)
                half3 normalTS = SampleNormal(uv, TEXTURE2D_ARGS(_BumpMap, sampler_BumpMap), _BumpScale);
                s.normalWS = NormalizeNormalPerPixel(TransformTangentToWorld(normalTS, tangentToWorld));
#else
                s.normalWS = s.corneaNormalWS;
#endif

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
                inputData.bakedGI = SAMPLE_GI(input.staticLightmapUV, input.vertexSH, s.normalWS);

                half4 shadowMask = CalculateShadowMask(inputData);
                AmbientOcclusionFactor aoFactor = CreateAmbientOcclusionFactor(inputData.normalizedScreenSpaceUV, occlusion);
                Light mainLight = GetMainLight(inputData, shadowMask, aoFactor);
                MixRealtimeAndBakedGI(mainLight, s.normalWS, inputData.bakedGI);

                // Ambient: the diffuse, and the environment mirrored in the cornea
                half NdotV = saturate(dot(s.corneaNormalWS, s.viewDirWS));
                half3 color = inputData.bakedGI * s.albedo * aoFactor.indirectAmbientOcclusion;
                half3 reflectVector = reflect(-s.viewDirWS, s.corneaNormalWS);
                half3 environment = GlossyEnvironmentReflection(reflectVector, inputData.positionWS, s.roughness, aoFactor.indirectAmbientOcclusion, inputData.normalizedScreenSpaceUV);
                color += environment * EnvironmentReflectance(s.reflectance, s.roughness, NdotV);

                color += EyeLighting(mainLight, s);

#if defined(_ADDITIONAL_LIGHTS)
                uint pixelLightCount = GetAdditionalLightsCount();
#if USE_FORWARD_PLUS || USE_CLUSTER_LIGHT_LOOP
                for (uint lightIndex = 0; lightIndex < min(URP_FP_DIRECTIONAL_LIGHTS_COUNT, MAX_VISIBLE_LIGHTS); lightIndex++)
                {
                    Light light = GetAdditionalLight(lightIndex, inputData, shadowMask, aoFactor);
#ifdef _LIGHT_LAYERS
                    if (IsMatchingLightLayer(light.layerMask, GetMeshRenderingLayer()))
#endif
                        color += EyeLighting(light, s);
                }
#endif
                LIGHT_LOOP_BEGIN(pixelLightCount)
                    Light light = GetAdditionalLight(lightIndex, inputData, shadowMask, aoFactor);
#ifdef _LIGHT_LAYERS
                    if (IsMatchingLightLayer(light.layerMask, GetMeshRenderingLayer()))
#endif
                        color += EyeLighting(light, s);
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

    // The error shader of every project, the URP one does not exist without URP
    FallBack "Hidden/InternalErrorShader"
}
