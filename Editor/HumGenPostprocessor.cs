// Sets up a Human Generator export the moment Unity imports it.
//
// Only files that the manifest of an export claims are touched (see HumGenExport), and the
// manifest says what every material is and which textures it has. The model becomes a Humanoid
// with its blend shapes, its animation files copy its avatar, the data textures get the right
// importer type, and every material gets the shader of the active render pipeline with its
// base color, normal and metallic-smoothness maps (the HDRP mask map with the occlusion
// remapped to one), hair cards as two-sided cutout (lit on both sides) with
// coverage-preserving mipmaps and, in URP, shaded as hair from the flow map of the export,
// the hair caps as fade and the skin with subsurface scattering in HDRP and the package's
// skin shader in URP.
using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using UnityEditor;
using UnityEditor.AssetImporters;
using UnityEngine;
using UnityEngine.Rendering;

namespace HumGen3D.Companion
{
    public sealed class HumGenPostprocessor : AssetPostprocessor
    {
        internal const string LogPrefix = "Human Generator 3D Companion: ";
        const string HairCutoutShader = "Human Generator 3D/Hair Cutout";
        const string HairCutoutUrpShader = "Human Generator 3D/Hair Cutout URP";
        /// <summary>
        /// Strand shading for the cards in URP: anisotropic highlights along the strands and a
        /// variation between them, from the flow map the export bakes for the cards (the direction of
        /// the strands on the card and a noise per strand). Cards without the map keep the cutout shader.
        /// </summary>
        const string HairUrpShader = "Human Generator 3D/Hair URP";
        // URP/Lit with a dithered alpha, for the haircaps
        const string HairCapUrpShader = "Human Generator 3D/Hair Cap URP";
        /// <summary>
        /// The skin in URP: the inputs and cost of URP/Lit with the light scattered under the skin
        /// (wrapped, red-tinted diffuse and shadow edges) and two specular lobes at skin reflectance.
        /// </summary>
        const string SkinUrpShader = "Human Generator 3D/Skin URP";
        // The caps fade out at the hairline; URP cuts them out here, see SetUpUniversal
        const float CapCutoff = 0.4f;
        // The defaults of the options (HumGenImportOptions) are 0.5 for the hair cutoff, the half
        // alpha Unity's alpha clipping defaults to, as the export bakes the strand coverage of the
        // hair atlas into the alpha, and 0.7 for the skin smoothness in URP: Blender renders the skin
        // with a fraction of the specular an engine gives a dielectric, at 1 the skin looked oiled.

        /// <summary>Bump when the import result changes, so cached imports are redone.</summary>
        public override uint GetVersion() => 10;

        /// <summary>Run after Unity's own material description preprocessors (Built-in 0, URP and HDRP 2).</summary>
        public override int GetPostprocessOrder() => 100;

        // ---------------------------------------------------------------- models

        void OnPreprocessModel()
        {
            var export = HumGenExport.FromModelPath(assetPath);
            if (export == null)
                return;
            context.DependsOnSourceAsset(export.ManifestPath);
            context.DependsOnCustomDependency(HumGenSettings.DependencyName);
            var options = HumGenImportOptions.For(assetImporter);
            if (!options.setUpCharacter)
                return;
            var importer = (ModelImporter)assetImporter;
            importer.importBlendShapes = true;
            if (importer.materialImportMode == ModelImporterMaterialImportMode.None)
                importer.materialImportMode = ModelImporterMaterialImportMode.ImportStandard;

            if (!options.humanoid)
            {
                // Generic, with an avatar of its own, so turning the option off undoes it
                importer.animationType = ModelImporterAnimationType.Generic;
                importer.avatarSetup = ModelImporterAvatarSetup.CreateFromThisModel;
                return;
            }
            importer.animationType = ModelImporterAnimationType.Human;
            if (export.IsClip)
            {
                // The clip file carries no character of its own; it animates the avatar of <Name>.fbx.
                // Both dependencies make the clip reimport once the model is there or changes, so the
                // import order does not matter; until then it is imported without an avatar.
                context.DependsOnSourceAsset(export.ModelPath);
                context.DependsOnArtifact(export.ModelPath);
                var avatar = AssetDatabase.LoadAssetAtPath<Avatar>(export.ModelPath);
                if (avatar != null)
                {
                    importer.avatarSetup = ModelImporterAvatarSetup.CopyFromOther;
                    importer.sourceAvatar = avatar;
                }
                else
                {
                    // Humanoid refuses NoAvatar; stay Generic until the model's avatar exists.
                    importer.animationType = ModelImporterAnimationType.Generic;
                    importer.avatarSetup = ModelImporterAvatarSetup.NoAvatar;
                }
            }
            else
            {
                importer.avatarSetup = ModelImporterAvatarSetup.CreateFromThisModel;
            }
        }

        void OnPostprocessModel(GameObject root)
        {
            var export = HumGenExport.FromModelPath(assetPath);
            if (export == null)
                return;
            if (!HumGenImportOptions.For(assetImporter).setUpCharacter)
                return;
            var fileName = System.IO.Path.GetFileName(assetPath);
            if (export.IsClip)
            {
                Debug.Log(LogPrefix + "set up " + fileName + " (clip of " + export.Name + ")");
                return;
            }
            var pipeline = DetectPipeline();
            Debug.Log(LogPrefix + "set up " + fileName + " (" + PipelineName(pipeline) + ")");
            var settings = HumGenSettings.instance;
            if (settings.warnWithoutMsaa)
                WarnWithoutMsaa(pipeline);
            // A new character: offer its import settings once the import is done. Not in batch
            // mode or in an import worker, where nobody is there to answer.
            if (assetImporter.importSettingsMissing && settings.showWindowOnFirstImport
                && !Application.isBatchMode && !AssetDatabase.IsAssetImportWorkerProcess())
            {
                var modelPath = export.ModelPath;
                EditorApplication.delayCall += () => HumGenImportWindow.Open(new[] { modelPath }, true);
            }
        }

        /// <summary>
        /// The hair card materials soften their cut-out edges with alpha to mask, which only does
        /// something when the camera renders with MSAA; the URP template ships with it off. The
        /// project settings are the user's, so this only says so.
        /// </summary>
        static void WarnWithoutMsaa(Pipeline pipeline)
        {
            int samples;
            string where;
            switch (pipeline)
            {
                case Pipeline.Universal:
                    var asset = GraphicsSettings.currentRenderPipeline;
                    var property = asset != null ? asset.GetType().GetProperty("msaaSampleCount") : null;
                    if (property == null)
                        return;
                    samples = (int)property.GetValue(asset);
                    where = "Anti Aliasing (MSAA) on the Universal Render Pipeline asset (" + asset.name + ")";
                    break;
                case Pipeline.BuiltIn:
                    samples = QualitySettings.antiAliasing;
                    where = "Anti Aliasing in Project Settings > Quality";
                    break;
                default:
                    return;
            }
            if (samples <= 1)
                Debug.LogWarning(LogPrefix + "MSAA is off in this project, so the edges of the hair cards stay hard. Set " + where + " to 4x for the soft edges the hair materials are set up for.");
        }

        // -------------------------------------------------------------- textures

        void OnPreprocessTexture()
        {
            var export = HumGenExport.FromTexturePath(assetPath, out var claims);
            if (export == null)
                return;
            context.DependsOnSourceAsset(export.ManifestPath);
            context.DependsOnCustomDependency(HumGenSettings.DependencyName);
            var options = HumGenImportOptions.For(assetImporter);
            if (!options.setUpCharacter)
                return;
            var importer = (TextureImporter)assetImporter;
            // A texture is normally a pass of one material; when materials share it, the hair
            // materials decide how its alpha is imported
            var claim = claims.OrderBy(c => c.Key.Kind == MaterialKind.Cards ? 0 : c.Key.Kind == MaterialKind.Cap ? 1 : 2).First();
            var kind = claim.Key.Kind;
            switch (claim.Value)
            {
                case "normal":
                    importer.textureType = TextureImporterType.NormalMap;
                    // Unity reads normal maps with green up (OpenGL)
                    importer.flipGreenChannel = export.Manifest.NormalMap == "directx";
                    break;
                case "metallic_smoothness":
                case "orm":
                case "metallic_roughness":
                case "roughness":
                case "metallic":
                case "alpha":
                case "flow":
                    importer.sRGBTexture = false;
                    break;
                case "base_color":
                    // Hair base colors carry their alpha; dilate the color into the transparent
                    // areas so the cutout and fade edges do not pick up the background color.
                    if (kind != MaterialKind.Opaque)
                        importer.alphaIsTransparency = true;
                    if (kind == MaterialKind.Cards)
                    {
                        // Averaging the alpha of thin strands for a mipmap drops it below the cutoff,
                        // so cut-out hair thinned out and vanished with distance. Unity can scale the
                        // alpha of every mip so the share of texels above the cutoff stays the same.
                        importer.mipMapsPreserveCoverage = true;
                        importer.alphaTestReferenceValue = options.hairCutoff;
                    }
                    else if (kind == MaterialKind.Cap && options.haircap == HaircapSetup.SetUp && DetectPipeline() == Pipeline.Universal)
                    {
                        // The caps are cut out in URP, see SetUpUniversal
                        importer.mipMapsPreserveCoverage = true;
                        importer.alphaTestReferenceValue = CapCutoff;
                    }
                    break;
            }
        }

        // ------------------------------------------------------------- materials

        enum Pipeline { BuiltIn, Universal, HighDefinition }

        // Unity creates the materials of a model through material descriptions by default
        // (materialImportMode ImportViaMaterialDescription) and then does not call
        // OnPostprocessMaterial, so both hooks lead to the same setup.
        void OnPreprocessMaterialDescription(MaterialDescription description, Material material, AnimationClip[] materialAnimation)
        {
            var name = string.IsNullOrEmpty(description.materialName) ? material.name : description.materialName;
            SetUpMaterial(material, name);
        }

        void OnPostprocessMaterial(Material material)
        {
            SetUpMaterial(material, material.name);
        }

        void SetUpMaterial(Material material, string materialName)
        {
            var export = HumGenExport.FromModelPath(assetPath);
            if (export == null || export.IsClip)
                return;
            // Only the materials the manifest lists, as what it says they are
            var exportMaterial = export.FindMaterial(materialName);
            if (exportMaterial == null)
                return;
            var options = HumGenImportOptions.For(assetImporter);
            if (!options.setUpCharacter)
                return;
            var kind = exportMaterial.Kind;
            if (kind == MaterialKind.Cap && options.haircap == HaircapSetup.AsImported)
                return;
            var baseColor = LoadTexture(exportMaterial, "base_color");
            var normal = LoadTexture(exportMaterial, "normal");
            var metallic = LoadTexture(exportMaterial, "metallic_smoothness");
            var flow = kind == MaterialKind.Cards && options.hairShading == HairShading.HairShader ? LoadTexture(exportMaterial, "flow") : null;
            var skin = exportMaterial.IsSkin;
            switch (DetectPipeline())
            {
                case Pipeline.Universal:
                    SetUpUniversal(material, kind, baseColor, normal, metallic, flow, skin, options);
                    break;
                case Pipeline.HighDefinition:
                    SetUpHighDefinition(material, kind, baseColor, normal, metallic, skin, options);
                    break;
                default:
                    SetUpBuiltIn(material, kind, baseColor, normal, metallic, options);
                    break;
            }
        }

        Texture LoadTexture(ExportMaterial material, string pass)
        {
            var path = material.Texture(pass);
            if (path == null || !System.IO.File.Exists(path))
                return null;
            context.DependsOnSourceAsset(path);
            return AssetDatabase.LoadAssetAtPath<Texture>(path);
        }

        static void SetUpBuiltIn(Material m, MaterialKind kind, Texture baseColor, Texture normal, Texture metallic, HumGenImportOptions options)
        {
            var hairCutout = kind == MaterialKind.Cards ? Shader.Find(HairCutoutShader) : null;
            m.shader = hairCutout != null ? hairCutout : Shader.Find("Standard");
            SetTexture(m, "_MainTex", baseColor);
            if (SetTexture(m, "_BumpMap", normal))
                m.EnableKeyword("_NORMALMAP");
            if (SetTexture(m, "_MetallicGlossMap", metallic))
            {
                m.SetFloat("_Metallic", 1f);
                m.SetFloat("_GlossMapScale", 1f);
                m.EnableKeyword("_METALLICGLOSSMAP");
            }
            switch (kind)
            {
                case MaterialKind.Cards when hairCutout != null:
                    m.SetFloat("_Cutoff", options.hairCutoff);
                    m.SetOverrideTag("RenderType", "TransparentCutout");
                    m.renderQueue = (int)RenderQueue.AlphaTest;
                    break;
                case MaterialKind.Cards:
                    // Standard shader cutout (one-sided) when the package shader is missing.
                    m.SetFloat("_Mode", 1f);
                    m.SetFloat("_Cutoff", options.hairCutoff);
                    m.SetOverrideTag("RenderType", "TransparentCutout");
                    m.SetInt("_SrcBlend", (int)BlendMode.One);
                    m.SetInt("_DstBlend", (int)BlendMode.Zero);
                    m.SetInt("_ZWrite", 1);
                    m.EnableKeyword("_ALPHATEST_ON");
                    m.DisableKeyword("_ALPHABLEND_ON");
                    m.DisableKeyword("_ALPHAPREMULTIPLY_ON");
                    m.renderQueue = (int)RenderQueue.AlphaTest;
                    break;
                case MaterialKind.Cap:
                    // Standard shader "Fade" rendering mode.
                    m.SetFloat("_Mode", 2f);
                    m.SetOverrideTag("RenderType", "Transparent");
                    m.SetInt("_SrcBlend", (int)BlendMode.SrcAlpha);
                    m.SetInt("_DstBlend", (int)BlendMode.OneMinusSrcAlpha);
                    m.SetInt("_ZWrite", 0);
                    m.DisableKeyword("_ALPHATEST_ON");
                    m.EnableKeyword("_ALPHABLEND_ON");
                    m.DisableKeyword("_ALPHAPREMULTIPLY_ON");
                    m.renderQueue = (int)RenderQueue.Transparent;
                    break;
            }
        }

        static void SetUpUniversal(Material m, MaterialKind kind, Texture baseColor, Texture normal, Texture metallic, Texture flow, bool skin, HumGenImportOptions options)
        {
            // The cards are shaded as hair when the export has their flow map. Otherwise, as
            // URP/Lit lights a back face with the normal of the front, they get the package's
            // copy of it that flips the normal; Lit when both shaders are missing.
            Shader packageShader = null;
            if (kind == MaterialKind.Cards)
            {
                packageShader = flow != null ? Shader.Find(HairUrpShader) : null;
                if (packageShader == null)
                    packageShader = Shader.Find(HairCutoutUrpShader);
            }
            if (kind == MaterialKind.Cap)
                packageShader = Shader.Find(HairCapUrpShader);
            // The skin gets the package's skin shader, which has the property set of Lit
            if (skin && options.skinShading == SkinShading.SkinShader)
                packageShader = Shader.Find(SkinUrpShader);
            m.shader = packageShader != null ? packageShader : Shader.Find("Universal Render Pipeline/Lit");
            SetTexture(m, "_BaseMap", baseColor);
            SetTexture(m, "_FlowMap", flow);
            if (SetTexture(m, "_BumpMap", normal))
                m.EnableKeyword("_NORMALMAP");
            if (SetTexture(m, "_MetallicGlossMap", metallic))
            {
                m.SetFloat("_Metallic", 1f);
                m.SetFloat("_Smoothness", 1f);
                m.SetFloat("_SmoothnessTextureChannel", 0f);
                m.EnableKeyword("_METALLICSPECGLOSSMAP");
                m.DisableKeyword("_SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A");
            }
            if (skin && metallic != null)
                m.SetFloat("_Smoothness", options.skinSmoothness);
            switch (kind)
            {
                case MaterialKind.Cards:
                    m.SetFloat("_AlphaClip", 1f);
                    m.SetFloat("_Cutoff", options.hairCutoff);
                    m.SetFloat("_Cull", (float)CullMode.Off);
                    // Alpha to coverage softens the cut-out edges when the camera uses MSAA
                    SetFloatIfPresent(m, "_AlphaToMask", 1f);
                    m.EnableKeyword("_ALPHATEST_ON");
                    m.SetOverrideTag("RenderType", "TransparentCutout");
                    m.renderQueue = (int)RenderQueue.AlphaTest;
                    break;
                case MaterialKind.Cap:
                    // URP (17, Unity 6000.6) does not draw a blended skinned cap at all: the
                    // transparent pass fails its depth test against the skin, whatever the blend
                    // state, while the same mesh draws as a cutout. A cutout makes a hard line
                    // of the fade towards the hairline, so the package's cap shader dithers it
                    // instead; CapCutoff is what casts a shadow, and what is drawn when the
                    // shader is missing.
                    m.SetFloat("_Surface", 0f);
                    m.SetFloat("_AlphaClip", 1f);
                    m.SetFloat("_Cutoff", CapCutoff);
                    m.SetFloat("_ZWrite", 1f);
                    m.SetFloat("_Cull", (float)CullMode.Back);
                    SetFloatIfPresent(m, "_AlphaToMask", packageShader != null ? 0f : 1f);
                    m.EnableKeyword("_ALPHATEST_ON");
                    m.DisableKeyword("_SURFACE_TYPE_TRANSPARENT");
                    m.DisableKeyword("_ALPHAPREMULTIPLY_ON");
                    m.SetOverrideTag("RenderType", "TransparentCutout");
                    m.renderQueue = (int)RenderQueue.AlphaTest;
                    break;
            }
            // Let URP's own material inspector code settle the keywords and render state, when it is around.
            var litKeywords = FindStaticMethod("UnityEditor.Rendering.Universal.ShaderGUI.LitGUI", "SetMaterialKeywords", 1);
            var baseKeywords = FindStaticMethod("UnityEditor.BaseShaderGUI", "SetMaterialKeywords", 3);
            if (baseKeywords != null)
            {
                var litAction = litKeywords != null ? Delegate.CreateDelegate(typeof(Action<Material>), litKeywords) : null;
                TryInvoke(baseKeywords, m, litAction, null);
            }
        }

        static void SetUpHighDefinition(Material m, MaterialKind kind, Texture baseColor, Texture normal, Texture metallic, bool skin, HumGenImportOptions options)
        {
            m.shader = Shader.Find("HDRP/Lit");
            SetTexture(m, "_BaseColorMap", baseColor);
            if (SetTexture(m, "_NormalMap", normal))
                m.EnableKeyword("_NORMALMAP");
            if (SetTexture(m, "_MaskMap", metallic))
            {
                // The HDRP mask map reads metallic from R, occlusion from G, the detail mask from
                // B and smoothness from A. The export's MetallicSmoothness map has metallic in
                // RGB and smoothness in A, so R and A are what HDRP/Lit wants. G would be read as
                // occlusion, so the occlusion remap is pinned to 1 and the channel is ignored; B
                // is only read when a detail map is assigned, which the export has none of.
                m.SetFloat("_MetallicRemapMin", 0f);
                m.SetFloat("_MetallicRemapMax", 1f);
                m.SetFloat("_AORemapMin", 1f);
                m.SetFloat("_AORemapMax", 1f);
                m.SetFloat("_SmoothnessRemapMin", 0f);
                m.SetFloat("_SmoothnessRemapMax", 1f);
                m.SetFloat("_Metallic", 1f);
                m.SetFloat("_Smoothness", 1f);
                m.EnableKeyword("_MASKMAP");
            }
            else
            {
                m.SetFloat("_Metallic", 0f);
                m.SetFloat("_Smoothness", 0.5f);
            }
            if (skin)
            {
                // Material type Subsurface Scattering: the skin of the export was rendered with
                // subsurface scattering in Blender and looks flat and harsh without it. HDRP
                // draws a subsurface material magenta unless its diffusion profile is one of
                // the profiles registered in the project, so a registered one is assigned, a
                // skin profile when there is one; without any the skin stays standard.
                var profile = options.skinShading == SkinShading.SkinShader ? RegisteredDiffusionProfile() : null;
                if (profile != null)
                {
                    m.SetFloat("_MaterialID", 0f);
                    SetFloatIfPresent(m, "_TransmissionEnable", 0f);
                    AssignDiffusionProfile(m, profile);
                }
                else
                {
                    m.SetFloat("_MaterialID", 1f);
                    if (options.skinShading == SkinShading.SkinShader)
                        Debug.Log(LogPrefix + "no diffusion profile is registered in the project, so the skin material "
                            + m.name + " is a standard material. Add a skin profile to the Diffusion Profile List of"
                            + " the default volume profile (Project Settings > Graphics > HDRP) and reimport for"
                            + " subsurface scattering.");
                }
            }
            switch (kind)
            {
                case MaterialKind.Cards:
                    m.SetFloat("_AlphaCutoffEnable", 1f);
                    m.SetFloat("_AlphaCutoff", options.hairCutoff);
                    m.SetFloat("_DoubleSidedEnable", 1f);
                    SetFloatIfPresent(m, "_CullMode", (float)CullMode.Off);
                    SetFloatIfPresent(m, "_CullModeForward", (float)CullMode.Off);
                    SetFloatIfPresent(m, "_AlphaToMask", 1f);
                    SetFloatIfPresent(m, "_AlphaToMaskInspectorValue", 1f);
                    m.EnableKeyword("_ALPHATEST_ON");
                    m.EnableKeyword("_DOUBLESIDED_ON");
                    m.SetOverrideTag("RenderType", "TransparentCutout");
                    m.renderQueue = (int)RenderQueue.AlphaTest;
                    break;
                case MaterialKind.Cap:
                    m.SetFloat("_SurfaceType", 1f);
                    m.SetFloat("_BlendMode", 0f);
                    SetFloatIfPresent(m, "_SrcBlend", (float)BlendMode.One);
                    SetFloatIfPresent(m, "_DstBlend", (float)BlendMode.OneMinusSrcAlpha);
                    SetFloatIfPresent(m, "_ZWrite", 0f);
                    m.EnableKeyword("_SURFACE_TYPE_TRANSPARENT");
                    m.EnableKeyword("_BLENDMODE_ALPHA");
                    m.SetOverrideTag("RenderType", "Transparent");
                    m.renderQueue = (int)RenderQueue.Transparent;
                    break;
            }
            // HDMaterial.ValidateMaterial sets up the keywords and passes from the properties above.
            var validate = FindStaticMethod("UnityEngine.Rendering.HighDefinition.HDMaterial", "ValidateMaterial", 1);
            if (validate != null)
                TryInvoke(validate, m);
        }

        static bool SetTexture(Material m, string property, Texture texture)
        {
            if (texture == null || !m.HasProperty(property))
                return false;
            m.SetTexture(property, texture);
            return true;
        }

        static void SetFloatIfPresent(Material m, string property, float value)
        {
            if (m.HasProperty(property))
                m.SetFloat(property, value);
        }

        // -------------------------------------------------------------- pipeline

        static Pipeline DetectPipeline()
        {
            var asset = GraphicsSettings.currentRenderPipeline;
            if (asset == null)
                return Pipeline.BuiltIn;
            var typeName = asset.GetType().Name;
            if (typeName.Contains("Universal"))
                return Pipeline.Universal;
            if (typeName.Contains("HDRenderPipeline"))
                return Pipeline.HighDefinition;
            return Pipeline.BuiltIn;
        }

        static string PipelineName(Pipeline pipeline)
        {
            switch (pipeline)
            {
                case Pipeline.Universal: return "URP";
                case Pipeline.HighDefinition: return "HDRP";
                default: return "Built-in";
            }
        }

        /// <summary>
        /// The first diffusion profile registered in the project, a skin profile when there is
        /// one. HDRP 17 keeps the registered profiles in the Diffusion Profile List of the default
        /// volume profile, HDRP 14 to 16 in the global settings. Null when none is registered.
        /// </summary>
        static UnityEngine.Object RegisteredDiffusionProfile()
        {
            var profiles = new List<UnityEngine.Object>();
            var volumeProfile = DefaultVolumeProfile();
            var components = volumeProfile != null
                ? volumeProfile.GetType().GetField("components")?.GetValue(volumeProfile) as System.Collections.IEnumerable
                : null;
            if (components != null)
                foreach (var component in components)
                {
                    if (component == null || component.GetType().Name != "DiffusionProfileList")
                        continue;
                    var parameter = component.GetType().GetField("diffusionProfiles")?.GetValue(component);
                    var value = parameter?.GetType().GetProperty("value")?.GetValue(parameter) as System.Collections.IEnumerable;
                    if (value != null)
                        foreach (var profile in value)
                            profiles.Add(profile as UnityEngine.Object);
                }
            if (profiles.Count == 0)
            {
                var globalType = FindType("UnityEngine.Rendering.HighDefinition.HDRenderPipelineGlobalSettings");
                var instance = globalType?.GetProperty("instance", BindingFlags.Public | BindingFlags.Static)?.GetValue(null);
                var list = instance != null ? globalType.GetField("diffusionProfileSettingsList")?.GetValue(instance) as System.Collections.IEnumerable : null;
                if (list != null)
                    foreach (var profile in list)
                        profiles.Add(profile as UnityEngine.Object);
            }
            profiles.RemoveAll(profile => profile == null);
            return profiles.FirstOrDefault(profile => profile.name.IndexOf("skin", StringComparison.OrdinalIgnoreCase) >= 0)
                ?? profiles.FirstOrDefault();
        }

        /// <summary>
        /// What HDMaterial.SetDiffusionProfile sets on the material: the hash of the profile,
        /// which the shader looks up in the registered list, and the GUID of its asset, which
        /// the material inspector shows. HDMaterial itself also records the profile among the
        /// external references of the material, which throws for a material that is being
        /// imported, so the two properties are set here.
        /// </summary>
        static void AssignDiffusionProfile(Material m, UnityEngine.Object profile)
        {
            const BindingFlags any = BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance;
            var inner = profile.GetType().GetField("profile", any)?.GetValue(profile);
            var hashValue = inner?.GetType().GetField("hash", any)?.GetValue(inner);
            if (hashValue == null)
                return;
            m.SetFloat("_DiffusionProfileHash", BitConverter.ToSingle(BitConverter.GetBytes(Convert.ToUInt32(hashValue)), 0));
            var guid = AssetDatabase.AssetPathToGUID(AssetDatabase.GetAssetPath(profile));
            if (guid.Length != 32 || !m.HasProperty("_DiffusionProfileAsset"))
                return;
            var bytes = new byte[16];
            for (int i = 0; i < 16; i++)
                bytes[i] = byte.Parse(guid.Substring(i * 2, 2), System.Globalization.NumberStyles.HexNumber);
            m.SetVector("_DiffusionProfileAsset", new Vector4(
                BitConverter.ToSingle(bytes, 0), BitConverter.ToSingle(bytes, 4),
                BitConverter.ToSingle(bytes, 8), BitConverter.ToSingle(bytes, 12)));
        }

        static UnityEngine.Object DefaultVolumeProfile()
        {
            var settingsType = FindType("UnityEngine.Rendering.HighDefinition.HDRPDefaultVolumeProfileSettings");
            var getter = typeof(GraphicsSettings).GetMethods(BindingFlags.Public | BindingFlags.Static)
                .FirstOrDefault(x => x.Name == "GetRenderPipelineSettings" && x.IsGenericMethod && x.GetParameters().Length == 0);
            if (settingsType == null || getter == null)
                return null;
            object settings;
            try { settings = getter.MakeGenericMethod(settingsType).Invoke(null, null); }
            catch { return null; }
            return settings?.GetType().GetProperty("volumeProfile")?.GetValue(settings) as UnityEngine.Object;
        }

        static Type FindType(string typeName)
        {
            foreach (var assembly in AppDomain.CurrentDomain.GetAssemblies())
            {
                Type type;
                try { type = assembly.GetType(typeName); }
                catch { continue; }
                if (type != null)
                    return type;
            }
            return null;
        }

        static MethodInfo FindStaticMethod(string typeName, string methodName, int parameterCount)
        {
            foreach (var assembly in AppDomain.CurrentDomain.GetAssemblies())
            {
                Type type;
                try { type = assembly.GetType(typeName); }
                catch { continue; }
                if (type == null)
                    continue;
                var method = type.GetMethods(BindingFlags.Public | BindingFlags.Static)
                    .FirstOrDefault(x => x.Name == methodName
                        && x.GetParameters().Length == parameterCount
                        && x.GetParameters()[0].ParameterType == typeof(Material));
                if (method != null)
                    return method;
            }
            return null;
        }

        static void TryInvoke(MethodInfo method, params object[] args)
        {
            try { method.Invoke(null, args); }
            catch (Exception e) { Debug.LogWarning(LogPrefix + method.DeclaringType.Name + "." + method.Name + " failed: " + e.Message); }
        }
    }
}
