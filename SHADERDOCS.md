# Shader Development Documentation

## Shaderpack Setup
Creating a shaderpack is fairly simple.
Simply create a folder in your `shaderpacks` folder with the name you'd like to use.
Inside this folder, you'll create subfolders and shader files (`.hlsl`) to create the various render passes, and set up configuration files (`.json`) to provide settings and various presets for users, as well as to define things such as the shader render order.

## Shader Settings
### General
Example settings file:
```json
{
    "postFx": [
        "pass1",
        "pass2"
    ]
}
```
The `postFx` list defines not only which postFx passes are included, but also in what order.
The first pass in the list gets rendered first.

### Per Shader
Example settings file:
```json
{
    "fields": {
        "test_field": {
            "disp": "Test Field",
            "desc": "A simple test field",
            "type": "float",
            "min": -1.0,
            "max":  1.0,
            "default": 0.0
        }
    },
    "textures": {
        "customLut": { "path": "path/to/file.dds", "id": 4 }
    }
}
```
The custom textures can be provided in .png format, but also as a .dds file.
TODO: More information on compatible .dds formats.
Keep in mind that the IDs must continue the ID sequence of already existing uniform texture IDs.

## Shader Passes
### PostFX
PostFX shaders are located inside the `your_pack/postFx` folder (note the uppercase F).

##### Uniforms
type | name | description
-----|------|------------
`texture0` | `backBuffer` | Contains the image currently on screen
`texture1` | `prepassBuffer` | TODO (seems related to decodeGBuffer stuff)
`texture2` | `prepassDepthBuffer` | Contains the prepass depth buffer
`texture3` | `rgba_noise_small` | Contains the RGBA noise small texture from shadertoy
 | | |
`float` | `totalTime` | Time in seconds since shader was loaded
`float` | `timeOfDay` | World time (0 = noon, 0.5 = midnight, 1.0 = noon the next day)
`float2` | `resolution` | Window resolution
 | | |
`float3` | `eyePosWorld` | Current position of the camera in world space
`float4` | `rtParams0` | TODO

##### Built-in Variables
These variables don't require a uniform to be used, and are simply always available.
type | name | description
-----|------|------------
`float4` | `projParams` | Holds data regarding the projection mapping. Can be used with decodeGBuffer to read normals/depth from the depth buffer.
