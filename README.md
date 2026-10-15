# Human Generator 3D Companion for Unity

Sets up a character exported with the **Unity** recipe of [Human Generator](https://humgen3d.com)'s
Process tab the moment Unity imports it, so nothing is left to do by hand. Drop the export
(`Name.fbx`, its `Name.humgen3d.json` manifest and its `Textures` folder) anywhere under `Assets`
and the companion takes it from there.

The companion only touches what the manifest of an export claims: the model and clip files it
lists, the materials it lists, and the texture files of those materials. The manifest also says
what every material is (skin, hair cards, haircap, eyes, ...) and which texture is which pass, so
the names of the files do not matter: the custom and Unreal naming schemes of the Process tab are
set up the same way. Without a manifest (an export of an older Human Generator, or a character
from anywhere else) Unity imports the file as it always does and the companion does nothing; set
it up by hand or export it again. A manifest of a newer export format than the companion knows is
skipped with a warning in the console to update the companion.

## What it does on import

**Model** (`Name.fbx`)
- Rig set to Humanoid with the avatar created from the model, blend shapes imported.
- One line in the console per character: `Human Generator 3D Companion: set up Jake.fbx (Built-in)`.

**Animation clips** (the animation files the manifest lists)
- Humanoid, avatar copied from the character file. The clip declares a dependency on the model, so
  the import order does not matter.

**Textures** (the texture files of the manifest's materials, by pass)
- Normal maps become normal maps, with the green channel flipped when the export wrote DirectX
  normal maps (`settings.textures.normal_map` in the manifest).
- Metallic-smoothness, ORM, metallic-roughness, roughness, metallic, alpha and flow maps are
  imported as linear data (sRGB off).
- The base colors of the hair cards and the haircaps get *Alpha Is Transparency* so the edges
  of the cards do not pick up the background color. The card textures also get *Preserve
  Coverage* mipmaps with the cutoff as reference, so the cut-out strands keep their width at a
  distance instead of thinning out.
  In URP the cap textures get the same, with the cap cutoff as reference.

**Materials**, per render pipeline (detected from the active render pipeline asset), by the type
the manifest gives them; the other materials get the base color, normal and metallic-smoothness
maps:

| | Built-in | URP | HDRP |
|---|---|---|---|
| Shader | `Standard` | `Universal Render Pipeline/Lit` | `HDRP/Lit` |
| Base color | `_MainTex` | `_BaseMap` | `_BaseColorMap` |
| Normal | `_BumpMap` + `_NORMALMAP` | `_BumpMap` + `_NORMALMAP` | `_NormalMap` + `_NORMALMAP` |
| Metallic-smoothness | `_MetallicGlossMap`, metallic 1, smoothness 1 | `_MetallicGlossMap`, metallic 1, smoothness 1, source alpha of the metallic map | `_MaskMap`, occlusion remap pinned to 1 (see below) |
| Hair cards (`hair_cards`) | `Human Generator 3D/Hair Cutout` (shipped in `Shaders/`), cutoff 0.5, `Cull Off`, alpha to mask | `Human Generator 3D/Hair URP` (shipped in `Shaders/`, see below) with the flow map of the cards, alpha clip 0.5, render face both, alpha to mask; `Human Generator 3D/Hair Cutout URP` without the map | alpha clipping 0.5, double-sided, alpha to mask |
| Hair caps (`haircap`, `face_haircap`) | rendering mode Fade | the Hair Cap URP shader: dithered alpha (URP 17 does not draw a blended skinned cap, see below) | surface type Transparent |
| Skin (`skin`) | | `Human Generator 3D/Skin URP` (shipped in `Shaders/`, see below), smoothness 0.7 | material type Subsurface Scattering with a diffusion profile registered in the project, standard without one (see below) |

The cutoff is the half alpha Unity defaults to: the export bakes the strand coverage of the hair
atlas into the alpha of the card textures, full strands with anti-aliased edges. Alpha to mask only
has an effect when the camera renders with MSAA.

**Skin in HDRP.** The skin of the export was rendered with subsurface scattering in Blender and
looks flat and harsh without it, so in HDRP the skin material gets the *Subsurface Scattering*
material type. HDRP draws a subsurface material magenta unless its diffusion profile is one of
the profiles registered in the project, so the companion assigns a registered one: the first
whose name contains "Skin" (the HDRP template registers HDRP's *SkinDiffusionProfile*), else the
first in the list. The list is the *Diffusion Profile List* of the default volume profile
(*Project Settings > Graphics > HDRP*; the global settings in HDRP 14 to 16). Without a registered
profile the skin stays a standard material and the console says so; register a skin profile and
reimport for subsurface scattering. Pick *Lit* under *Skin* in the import settings for a standard
material in any case. The Built-in pipeline has no subsurface scattering in its Standard shader,
the skin stays a plain Standard material there.

**Skin in URP.** URP/Lit has no subsurface scattering either: the skin got a hard, grey line
where it turns from the light, and the smoothness map at the reflectance Lit gives every
dielectric (0.04) made it look oiled. The companion assigns `Human Generator 3D/Skin URP`, which
approximates the scattering the way games usually do in a forward renderer, without a
screen-space pass or a lookup texture:

- the light wraps past the shadow line, furthest in red (*Subsurface Color*, *Scatter Width*),
  and the edges of shadows get the same warm fringe;
- the red light ignores most of the detail of the normal map and blue keeps it (*Normal Blur*),
  so pores and wrinkles stay sharp without the skin looking rough;
- the ambient light is sampled with the normal of the mesh, so the normal map does not darken
  the skin in the shade;
- the specular is two GGX lobes at the reflectance of skin (*Reflectance* 0.028), a sharp and
  a broad one (*Sharp Lobe Roughness*, *Broad Lobe Roughness*, *Sharp Lobe Share*), and the
  environment reflection uses a split-sum fit for a dielectric, so the edges of the face do not
  turn into a wet rim.

The import also sets *Smoothness* (the multiplier of the smoothness map) to 0.7: Blender renders
the skin with a fraction of the specular an engine gives a dielectric. The shader has the
property names of URP/Lit (`_BaseMap`, `_BumpMap`, `_MetallicGlossMap`, `_OcclusionMap`,
`_Smoothness`, the surface options), so switching the material to Lit and back keeps its
textures and settings, and it reads an occlusion map when you assign one. It is SRP Batcher
compatible, renders in Forward, Forward+ and Deferred (forward-only, like the hair), and has the
ShadowCaster, DepthOnly and DepthNormalsOnly passes, so SSAO and decals work. Specular
Highlights and Environment Reflections can be switched off as in Lit. It has no MotionVectors
pass (URP 14 cannot compile one), no lightmapping meta pass and no DOTS instancing block.
Should the shader be missing, the skin falls back to URP/Lit.

The caps fade out at the hairline and are blended in Built-in and HDRP. URP 17 (Unity 6000.6)
does not draw a blended cap on a skinned mesh at all: its transparent pass fails the depth test
against the skin whatever the blend state, so the scalp showed skin under the hair. In URP the
companion gives the caps its Hair Cap URP shader instead, which draws them opaque with a dithered
alpha: every pixel of the fade towards the hairline is drawn or not by a noise over the screen,
which temporal or multisample anti-aliasing blends into a soft hairline. The cutoff of 0.4 is
what casts a shadow.

Alpha to mask only softens the edges when the camera renders with MSAA, which the URP template
turns off: the companion logs a warning on import when MSAA is off in a Built-in or URP project
(set *Anti Aliasing (MSAA)* to 4x on the URP asset, or *Anti Aliasing* in the Quality settings).

The Built-in `Standard` shader has no two-sided option, and URP/Lit renders both faces but lights
a back face with the normal of the front, so a card seen from behind went dark or lit up from the
wrong side. The package ships a hair shader for each: a surface shader for Built-in with the
albedo, normal and metallic-smoothness inputs of `Standard`, and a copy of URP/Lit with the same
inputs and inspector; both flip the normal on back faces. Should a shader be missing from the
project, the cards fall back to the one-sided cutout mode of `Standard` or to URP/Lit.

**Hair shading in URP.** Lit as a flat surface, a card has its highlight across the card and
mirrors the sky; hair reflects along its strands. Human Generator 4.0.28 and later bake a flow map
for the cards (the `flow` pass of the cards in the manifest: the direction of the strands on the card in RG, a noise
per strand in B). With it the companion assigns `Human Generator 3D/Hair URP`: a Kajiya-Kay strand
model with a white and a color-tinted highlight that run along the strands and are shifted apart,
broken up between strands by the noise, which also varies the color from strand to strand, with
the diffuse wrapped so a card does not go black where a round bundle would still catch light, no
environment reflections, two-sided and alpha tested like the cutout shader, and the same Lit
property set, so the depth and shadow passes of Lit apply. Its strengths, shifts and exponents
are material properties. The material is not SRP Batcher compatible (its hair properties live
outside the Lit constant buffer); a character has one or two of them. Built-in and HDRP keep the
cutout materials.

**Metallic-smoothness in HDRP.** HDRP/Lit reads one mask map: metallic from R, occlusion from
G, the detail mask from B and smoothness from A. The `MetallicSmoothness` texture of the export
has metallic in RGB and smoothness in A, so R and A are already what HDRP wants. The companion
assigns it as the mask map and pins the *Ambient Occlusion Remapping* to 1, so the G channel
(which would read as occlusion) is ignored; B is only read when a detail map is assigned, and the
export has none. Metallic and smoothness remapping stay at 0 to 1. To add baked occlusion later,
paint it into G and reset the occlusion remap.

What Unity already does by itself with the plain export (Humanoid mapping, base color and normal
assignment, LOD groups) and what it does not is on the
[Export to Unity](https://humgen3d.com/docs/process/export-to-unity) page.

## Import settings

Everything above is the default; what the companion sets up can be changed in two places.

**Project defaults**: *Edit > Project Settings > Human Generator 3D*. Stored in
`ProjectSettings/HumGen3DCompanion.asset`, so they go into version control with the project.
*Apply* reimports the characters that use the defaults (through a custom dependency of their
import; pulling a changed settings file does the same).

**Per character**: right-click the `.fbx` and choose *Human Generator 3D > Import Settings...*
(also in the *Human Generator 3D* menu, for several selected characters at once). Turn off *Use
the project defaults*, change the options and press *Apply*. The options are stored in the
`userData` of the importers of the export's files (the model, its textures and its clips, in
their `.meta` files), so they are kept on every reimport and travel with the files. If a file's
`userData` already holds data of another tool, the window says so and leaves that file alone,
except the model itself.

The window also opens by itself after a new character was imported in the editor, with the
defaults it was imported with; close it to keep them. Never in batch mode or an import worker,
so builds and CI never wait on it. *Show Window On Import* in the project settings turns it off.

| Option | Default | What it does |
|---|---|---|
| Set Up Character | on | Off leaves the export as Unity imports it |
| Humanoid | on | Humanoid rig with an avatar from the model, copied by the clips; off sets the rig to Generic |
| Card Shading | Hair Shader | URP: *Cutout* lights the cards as flat surfaces with the Hair Cutout URP shader. Built-in and HDRP always cut out |
| Card Cutoff | 0.5 | Alpha below which a card texel is cut out, also the reference of the coverage-preserving mipmaps |
| Haircap | Set Up | *As Imported* leaves the haircap materials as Unity made them (in URP 17 a blended cap does not draw, see above) |
| Skin Shader (URP) | Skin Shader | *Lit* gives the skin Universal Render Pipeline/Lit |
| Skin Smoothness (URP) | 0.7 | Multiplier of the smoothness map of the skin |

The project settings also hold *Warn Without MSAA* (on), the console warning about MSAA below.

## Install

The download and the install steps are on
[humgen3d.com/docs/process/unity-companion](https://humgen3d.com/docs/process/unity-companion).

Tested with Unity 6000.6.5f1 in the Built-in render pipeline and URP 17.2. HDRP materials are
set up (see above) but have not been reviewed in a rendered scene. The package declares Unity
2022.3 as its minimum, but older versions than 6000.6 have not been tested.

Exports need the `Name.humgen3d.json` manifest, which Human Generator writes next to every
exported character; exports of versions before the manifest are not set up.

## Characters imported before the companion was installed

Select the character's `.fbx` (or the folder it is in) in the Project window and run
*Human Generator 3D > Set Up Selected Characters*. It reimports the textures, the model and the
clip files of its manifest, which runs the setup above.

## Import check

`Editor/HumGenCheck.cs` imports the exported FBX found under `Assets/HumGen` in batch mode and
writes `report.json` to the project folder: the manifests found, the avatar mapping, per material
the shader, maps, cutout and cull values, the texture importer types, the blend shapes, clips and
the companion's log lines. In a project that has the package:

```
mkdir -p Assets/HumGen && cp -r <export folder>/* Assets/HumGen/
Unity -batchmode -nographics -projectPath . -executeMethod HumGenCheck.Run -quit -logFile check.log
```

Add `-humgenFolder Assets/Other` to check a different folder.

## Status

Early access. Built-in and URP 17.2 are verified on Unity 6000.6.5f1 with the import check and in
rendered scenes. HDRP (17.6) was checked with the import check only: the materials, maps,
keywords and remap values come out as described above, but the look has not been reviewed. Feedback on what the
export should set up for you goes to
[https://humgen3d.com/feedback/process](https://humgen3d.com/feedback/process).

## License

MIT. The Human Generator add-on for Blender is a separate, paid product; this companion works on
what it exports.
