# Shader Development Documentation

## Shaderpack Setup
Creating a shaderpack is fairly simple.
Simply create a folder in your `shaderpacks` folder with the name you'd like to use.
Inside this folder, you'll create subfolders and shader files (`.hlsl`) to create the various render passes, and set up configuration files (`.json`) to provide settings and various presets for users, as well as to define things such as the shader render order.

## Shader Settings
### General
<TODO> Example settings file:
```json
{

}
```

### Per Shader
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
    }
}
```

## Shader Passes
### PostFX
PostFX shaders are located inside the `your_pack/postFx` folder (note the uppercase F).

Their possible uniforms are as follows:

type | name | description
-----|------|------------
`texture0` | `backBuffer` | Contains the image currently on screen
`texture1` | `prepassDepthBuffer` | Contains the prepass depth buffer
`texture2` | `rgba_noise_small` | Contains the RGBA noise small texture from shadertoy
 | | |
`float` | `totalTime` | Time in seconds since shader was loaded
`float` | `timeOfDay` | World time (0 = noon, 0.5 = midnight, 1.0 = noon the next day)

##### Vanilla BeamNG shader uniforms.
type | name | description
-----|------|------------
`float3` | `eyePosWorld` | Current position of the camera in world space
