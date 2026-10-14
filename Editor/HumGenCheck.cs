// Import check: imports the exported FBX found under Assets/HumGen and writes report.json with what the
// companion set up: avatar mapping, materials (shader, maps, cutout and cull values), texture importer
// types, blend shapes, clips and the companion's log lines.
// Run: Unity -batchmode -nographics -projectPath <project> -executeMethod HumGenCheck.Run -quit
// Another folder: add -humgenFolder <project-relative folder> to the command line.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;

public static class HumGenCheck
{
    static readonly List<string> log = new List<string>();
    static readonly List<string> companionLog = new List<string>();

    static readonly string[] reportedFloats =
    {
        "_Mode", "_Cutoff", "_AlphaClip", "_Cull", "_Surface", "_Blend", "_ZWrite",
        "_AlphaCutoffEnable", "_AlphaCutoff", "_DoubleSidedEnable", "_CullMode", "_SurfaceType",
        "_Metallic", "_GlossMapScale", "_Smoothness", "_AlphaToMask", "_MaterialID",
        "_MetallicRemapMin", "_MetallicRemapMax", "_AORemapMin", "_AORemapMax", "_SmoothnessRemapMin", "_SmoothnessRemapMax",
    };

    public static void Run()
    {
        Application.logMessageReceived += (msg, stack, type) =>
        {
            if (type != LogType.Log) log.Add(type + ": " + msg);
            else if (msg.Contains("Human Generator 3D Companion")) companionLog.Add(msg);
        };
        var report = new Dictionary<string, object>();
        try
        {
            var folder = Argument("-humgenFolder") ?? "Assets/HumGen";
            var pipeline = GraphicsSettings.currentRenderPipeline;
            report["pipeline"] = pipeline != null ? pipeline.GetType().Name : "Built-in";
            var fbxPath = Directory.GetFiles(folder, "*.fbx", SearchOption.AllDirectories)
                .Select(p => p.Replace("\\", "/")).Where(p => !Path.GetFileName(p).Contains("@")).First();
            report["fbx"] = fbxPath;
            report["manifests"] = Directory.GetFiles(folder, "*.humgen3d.json", SearchOption.AllDirectories).Select(p => p.Replace("\\", "/")).ToList();
            AssetDatabase.ImportAsset(fbxPath, ImportAssetOptions.ForceSynchronousImport);
            var importer = AssetImporter.GetAtPath(fbxPath) as ModelImporter;
            report["importer_animation_type"] = importer.animationType.ToString();
            report["importer_avatar_setup"] = importer.avatarSetup.ToString();
            report["importer_blend_shapes"] = importer.importBlendShapes;

            var go = AssetDatabase.LoadAssetAtPath<GameObject>(fbxPath);
            var animator = go.GetComponent<Animator>();
            var avatar = animator != null ? animator.avatar : null;
            report["avatar_valid"] = avatar != null && avatar.isValid;
            report["avatar_human"] = avatar != null && avatar.isHuman;
            var mapped = avatar != null ? avatar.humanDescription.human.Select(h => h.humanName).ToList() : new List<string>();
            var all = HumanTrait.BoneName.ToList();
            report["human_bones_mapped"] = mapped.Count;
            report["human_bones_total"] = all.Count;
            report["human_bones_unmapped"] = all.Where(b => !mapped.Contains(b)).ToList();
            report["lod_group"] = go.GetComponentInChildren<LODGroup>() != null;
            report["scale"] = go.transform.localScale.x;
            var bounds = new List<float>();
            foreach (var r in go.GetComponentsInChildren<SkinnedMeshRenderer>()) bounds.Add(r.bounds.size.y);
            report["height_m"] = bounds.Count > 0 ? bounds.Max() : 0f;

            var materials = new List<Dictionary<string, object>>();
            foreach (var r in go.GetComponentsInChildren<Renderer>())
            {
                foreach (var m in r.sharedMaterials)
                {
                    if (m == null) { materials.Add(new Dictionary<string, object> { { "renderer", r.name }, { "material", "null" } }); continue; }
                    var entry = new Dictionary<string, object> { { "renderer", r.name }, { "material", m.name }, { "shader", m.shader.name } };
                    entry["baseColor"] = TextureName(m, "_MainTex", "_BaseMap", "_BaseColorMap");
                    entry["normalMap"] = TextureName(m, "_BumpMap", "_NormalMap");
                    entry["metallicMap"] = TextureName(m, "_MetallicGlossMap", "_MaskMap");
                    entry["metallicMapAssigned"] = entry["metallicMap"] != null;
                    entry["renderQueue"] = m.renderQueue;
                    entry["renderType"] = m.GetTag("RenderType", false, "");
                    entry["keywords"] = m.shaderKeywords.OrderBy(k => k).ToList();
                    foreach (var property in reportedFloats)
                        if (m.HasProperty(property)) entry[property] = m.GetFloat(property);
                    materials.Add(entry);
                }
                var smr = r as SkinnedMeshRenderer;
                if (smr != null && smr.sharedMesh != null && smr.sharedMesh.blendShapeCount > 0)
                    report["blend_shapes_" + r.name] = smr.sharedMesh.blendShapeCount;
            }
            report["materials"] = materials;

            var textures = new List<Dictionary<string, object>>();
            foreach (var t in AssetDatabase.FindAssets("t:Texture", new[] { folder }))
            {
                var p = AssetDatabase.GUIDToAssetPath(t);
                var ti = AssetImporter.GetAtPath(p) as TextureImporter;
                textures.Add(new Dictionary<string, object>
                {
                    { "file", Path.GetFileName(p) },
                    { "type", ti != null ? ti.textureType.ToString() : "?" },
                    { "sRGB", ti != null && ti.sRGBTexture },
                    { "flipGreenChannel", ti != null && ti.flipGreenChannel },
                    { "alphaIsTransparency", ti != null && ti.alphaIsTransparency },
                    { "mipMapsPreserveCoverage", ti != null && ti.mipMapsPreserveCoverage },
                    { "alphaTestReferenceValue", ti != null ? ti.alphaTestReferenceValue : 0f },
                });
            }
            report["textures"] = textures;
            var clips = new List<Dictionary<string, object>>();
            foreach (var clipFile in Directory.GetFiles(folder, "*@*.fbx", SearchOption.AllDirectories).Select(p => p.Replace("\\", "/")))
            {
                var clipImporter = AssetImporter.GetAtPath(clipFile) as ModelImporter;
                clips.Add(new Dictionary<string, object>
                {
                    { "file", clipFile },
                    { "animationType", clipImporter != null ? clipImporter.animationType.ToString() : "?" },
                    { "avatarSetup", clipImporter != null ? clipImporter.avatarSetup.ToString() : "?" },
                    { "sourceAvatar", clipImporter != null && clipImporter.sourceAvatar != null ? clipImporter.sourceAvatar.name : null },
                    { "clips", AssetDatabase.LoadAllAssetsAtPath(clipFile).OfType<AnimationClip>().Select(c => c.name).Where(n => !n.StartsWith("__preview__")).ToList() },
                });
            }
            report["clips"] = clips;
        }
        catch (Exception e)
        {
            report["exception"] = e.ToString();
        }
        report["companion_log"] = companionLog;
        report["log"] = log;
        File.WriteAllText("report.json", MiniJson(report));
        Debug.Log("REPORT WRITTEN");
        EditorApplication.Exit(0);
    }

    static string TextureName(Material m, params string[] properties)
    {
        foreach (var property in properties)
            if (m.HasProperty(property) && m.GetTexture(property) != null) return m.GetTexture(property).name;
        return null;
    }

    static string Argument(string name)
    {
        var args = Environment.GetCommandLineArgs();
        var index = Array.IndexOf(args, name);
        return index >= 0 && index + 1 < args.Length ? args[index + 1] : null;
    }

    // Minimal JSON writer, enough for the report (JsonUtility can't do dictionaries)
    static string MiniJson(object o)
    {
        switch (o)
        {
            case null: return "null";
            case string s: return "\"" + s.Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\n", "\\n") + "\"";
            case bool b: return b ? "true" : "false";
            case float f: return f.ToString(System.Globalization.CultureInfo.InvariantCulture);
            case int i: return i.ToString();
            case Dictionary<string, object> d: return "{" + string.Join(",", d.Select(kv => MiniJson(kv.Key) + ":" + MiniJson(kv.Value))) + "}";
            case System.Collections.IEnumerable e: return "[" + string.Join(",", e.Cast<object>().Select(MiniJson)) + "]";
            default: return MiniJson(o.ToString());
        }
    }
}
