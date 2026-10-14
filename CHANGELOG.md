# Changelog

## 0.7.0

- The companion sets up an export only through its manifest, the `<Name>.humgen3d.json` file
  Human Generator writes next to every exported character. Only the model and clip files the
  manifest lists, the materials it lists and the texture files of those materials are touched.
  **Exports without a manifest, from Human Generator versions before it, are no longer set up**:
  Unity imports them as they are; export them again or set them up by hand. The recognition by
  the `<Name>_Skin_BaseColor` texture is gone.
- Materials are set up by the type the manifest gives them (skin, hair cards, haircap, ...) and
  get the texture files the manifest lists for them, instead of going by the suffixes of the
  names (`*_Skin`, `*Cards`, `<Material>_<Pass>`), so exports with the custom and Unreal naming
  schemes are set up as well. Textures are imported by their pass in the manifest.
- Normal maps get their green channel flipped when the manifest says the export wrote DirectX
  normal maps.
- A manifest of a newer export format than the companion reads is skipped, with a warning (once
  per manifest) to update the companion.
- The import of a character and its textures depends on the manifest, so a changed manifest
  reimports them.
- The per-file import options and `ProjectSettings/HumGen3DCompanion.asset` carry a `version`
  (1), and the option enums have fixed numbers, so later versions can migrate stored settings.
- The import check reports the manifests it found and whether a normal map is flipped.
- README: install steps on humgen3d.com, the tested Unity versions and pipelines.

## 0.6.0

- Import settings. Project defaults under *Project Settings > Human Generator 3D*, stored in
  `ProjectSettings/HumGen3DCompanion.asset`; applying them reimports the characters that use
  them. Per character, *Human Generator 3D > Import Settings...* on the `.fbx` overrides them,
  stored in the `userData` of the importers of the export's files. The options: set up the
  character at all, Humanoid (Generic when off), card shading (hair shader or cutout), card
  cutoff, haircap set up or as imported, skin shader or Lit (URP), skin smoothness (URP); and
  in the project settings the MSAA warning and whether the window opens after a new character
  was imported (never in batch mode). The defaults are what 0.5.0 did.

## 0.5.0

- URP: the skin (`*_Skin`) gets the shipped `Human Generator 3D/Skin URP` shader instead of
  URP/Lit: the light wraps past the shadow line and around shadow edges, furthest in red, the
  red light ignores most of the detail of the normal map, and the specular is two GGX lobes at
  skin reflectance (0.028) with a split-sum environment term. URP/Lit gave the skin a hard grey
  terminator and an oiled look. The shader has the property names of URP/Lit, is SRP Batcher
  compatible and costs about as much as Lit; its scattering and lobes are material properties.
- URP: the skin's *Smoothness* is set to 0.7 (it was 1).

## 0.4.0

- URP: the `*Cards` materials are shaded as hair with the shipped `Human Generator 3D/Hair
  URP` shader when the export has their `*Cards_Flow` map (Human Generator 4.0.28 and later):
  a Kajiya-Kay strand model with a white and a color-tinted highlight that run along the
  strands and are shifted apart, the strand direction and a noise per strand read from the
  flow map, which also varies the color between strands. No environment reflections, so the
  cards stop mirroring the sky. Exports without the map keep the Hair Cutout URP shader.
- `*_Flow` textures are imported as linear data.
- The Hair URP shader fades a card out when the camera looks along it (`Edge Fade`, 0.25; 0
  turns it off), where it would be a line with all its strands pressed into it. The card keeps
  a share of its alpha (`Edge Fade Floor`, 0.7), so the solid strands stay and no tip of a lock
  is left floating in the air. Its depth passes fade the same pixels.
- The Hair URP shader takes the axes of a card from the screen where the tangents of the mesh
  are invalid, and turns the normal towards the camera by its own direction instead of by the
  face. The normals of the cards follow the shape of the head, so cards that stand on the head
  or cross another card were lit wrongly, triangle by triangle.
- URP: the haircaps (`*_Haircap`, `*_FaceHair`) get the shipped `Human Generator 3D/Hair Cap
  URP` shader, URP/Lit with a dithered alpha in the color and depth passes. The cut-out at 0.4
  they had turned the fade of the cap towards the hairline into a hard, jagged line beyond the
  first cards; dithered, the fade is soft with temporal or multisample anti-aliasing. The
  cutoff is still what casts a shadow.


## 0.3.0

- HDRP: the `*_MetallicSmoothness` texture is assigned as the mask map of HDRP/Lit, with the
  ambient occlusion remap pinned to 1 so the G channel (metallic in the export, occlusion for
  HDRP) is ignored. Metallic and smoothness come from R and A as in the other pipelines; the
  mask map was left empty before, with metallic 0 and smoothness 0.5 on every material.
- The import check reports the HDRP remap values.

## 0.2.0

- Hair cards are cut out at alpha 0.5, the Unity default, as the export now bakes the strand
  coverage of the hair atlas into the alpha instead of the translucent alpha of the Blender
  material.
- `*Cards` base color textures get coverage-preserving mipmaps with the cutoff as reference, so
  the strands keep their width at a distance.
- Hair card materials get alpha to mask (URP, HDRP and the shipped Built-in shader), which
  softens the cut-out edges when the camera uses MSAA.
- A warning on import when MSAA is off in the project, as alpha to mask does nothing without it.
- Hair cards are lit on both sides: the shipped Built-in shader flips the normal on back faces,
  and URP gets a shipped copy of URP/Lit that does the same (`Human Generator 3D/Hair Cutout
  URP`), as URP/Lit lit a back face with the normal of the front.
- HDRP: the `*_Skin` material gets the Subsurface Scattering material type, with the default
  diffusion profile of the project.
- The import check reports the mipmap and material type settings.
- URP: the `*_Haircap` and `*_FaceHair` materials are cut out at alpha 0.4 with alpha to mask
  instead of blended. URP 17 (Unity 6000.6) does not draw a blended skinned cap at all: its
  transparent pass fails the depth test against the skin, whatever the blend state, so the scalp
  showed skin under the hair. Cut out, the cap draws; MSAA softens the hairline. Built-in keeps
  the Fade material. The cap textures get coverage-preserving mipmaps in URP.

## 0.1.0

First version of the Human Generator 3D Companion for Unity.

- Recognises Human Generator exports by their `<Name>_Skin_BaseColor` texture in a `Textures`
  folder next to the model or next to the file; nothing else in the project is touched.
- Models are imported as Humanoid with the avatar created from the model and blend shapes on.
- `<Name>@<Clip>.fbx` animation clips are imported as Humanoid with the avatar copied from
  `<Name>.fbx`, with a dependency on the model so the import order does not matter.
- `*_Normal` textures are imported as normal maps; `*_MetallicSmoothness`, `*_ORM`,
  `*_MetallicRoughness`, `*_Roughness`, `*_Metallic` and `*_Alpha` textures as linear data;
  hair base colors get *Alpha Is Transparency*.
- Materials get the shader of the active render pipeline (Built-in `Standard`,
  `Universal Render Pipeline/Lit`, `HDRP/Lit`) with the base color, normal and
  metallic-smoothness maps assigned and the matching keywords. HDRP leaves the mask map empty
  because its channel layout differs from the export.
- `*Cards` hair materials become two-sided cutout at 0.3; Built-in uses the shipped
  `Human Generator 3D/Hair Cutout` surface shader because `Standard` cannot render two-sided.
- `*_Haircap` and `*_FaceHair` cap materials become fade / transparent.
- Menu item *Human Generator 3D > Set Up Selected Characters* reimports selected exports
  (textures, model and clips) for characters imported before the package was installed.
- One console line per processed model.
- Import check (`HumGenCheck.Run`) reports per material the shader, maps, cutout and cull
  values, the texture importer types, the avatar mapping, blend shapes and clips.
