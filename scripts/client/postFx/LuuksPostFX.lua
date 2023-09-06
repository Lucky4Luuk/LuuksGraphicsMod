local LuuksPostFX = {}

local rootPath = "shaderpacks"
local tempPath = "temp/shaders/lgm_tmp"

local totalTime = 0

LuuksPostFX.shaderPacks = {}

local function updateUniforms(selectedPack, dt)
    if LuuksPostFX.shaderPacks[selectedPack] == nil then return end

    totalTime = totalTime + dt

    local tod = core_environment.getTimeOfDay()

    -- local camForward = core_camera.getForward()
    -- local camPosition = core_camera.getPosition()
    -- camPosition = { x = camPosition.x, y = camPosition.y, z = camPosition.z }
    -- local camFovDeg = core_camera.getFovDeg()

    for i, shader in pairs(LuuksPostFX.shaderPacks[selectedPack].shaders) do
        local fx = scenetree.findObject("LGM_" .. shader.name .. "_Fx")
        if fx then
            fx:setShaderConst("$totalTime", totalTime)
            fx:setShaderConst("$timeOfDay", tod.time)
            -- fx:setShaderConst("$camPos", camPosition)
        end
    end
end

local function isFile(path)
    return FS:stat(path).filetype ~= "dir"
end

local function removeOldShaders()
    if FS:directoryExists(tempPath) then
        FS:directoryRemove(tempPath)
    end
end

local function loadShaderPostFX(path, name)
    print("[LGM] Loading " .. name .. " (" .. path .. ")")
    local pfxDefaultStateBlock = scenetree.findObject("PFX_DefaultStateBlock")
    stateBlock = createObject("GFXStateBlockData")
    stateBlock:inheritParentFields(pfxDefaultStateBlock)
    stateBlock.samplersDefined = true
    stateBlock:setField("samplerStates", 0, "SamplerClampLinear")
    stateBlock:setField("samplerStates", 1, "SamplerClampLinear")
    stateBlock:setField("samplerStates", 2, "SamplerClampPoint")
    stateBlock:registerObject("LGM_" .. name .. "_StateBlock")

    local shader = scenetree.findObject("LGM_" .. name .. "_ShaderData")
    if not shader then
        shader = createObject("ShaderData")
        shader.DXVertexShaderFile = "shaders/common/postFx/postFxV.hlsl"
        shader.DXPixelShaderFile = path
        shader.pixVersion = 2.0
        shader:registerObject("LGM_" .. name .. "_ShaderData")
    end

    local fx = scenetree.findObject("LGM_" .. name .. "_Fx")
    if not fx then
        fx = createObject("PostEffect")
        fx.isEnabled = false
        fx.allowReflectPass = false
        fx:setField("renderTime", 0, "PFXAfterDiffuse")
        -- fx:setField("renderTime", 0, "PFXBeforeBin")
        -- fx:setField("renderBin", 0, "AfterPostFX")
        fx.renderPriority = 0.8

        fx:setField("stateBlock", 0, "LGM_" .. name .. "_StateBlock")

        fx:setField("shader", 0, "LGM_" .. name .. "_ShaderData")
        fx:setField("stateBlock", 0, "PFX_DefaultStateBlock")
        fx:setField("texture", 0, "$backBuffer")
        fx:setField("texture", 1, "#prepass[Depth]")
        fx:setField("texture", 2, "scripts/client/postFx/rgba_noise_small.dds")
        -- fx:setField("texture", 2, "#prepass[RT0]")

        -- fx:setField("totalTime", 0, 0.0)

        fx:registerObject("LGM_" .. name .. "_Fx")
    end
end

-- From: https://stackoverflow.com/a/7615129
function strsplit (inputstr, sep)
        if sep == nil then
            sep = "%s"
        end
        local t={}
        for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
            table.insert(t, str)
        end
        return t
end

local function loadShaders()
    print("Loading shaders from " .. rootPath .. "...")
    if not FS:directoryExists(rootPath) then FS:directoryCreate(rootPath) end
    if not FS:directoryExists(tempPath) then FS:directoryCreate(tempPath) end

    LuuksPostFX.shaderPacks = {}

    for i, item in pairs(FS:directoryList(rootPath)) do
        if not isFile(item) then
            local pack = { name = item, shaders = {} }
            if FS:directoryExists(item .. "/postFx") then
                for j, file in pairs(FS:directoryList(item .. "/postFx")) do
                    if isFile(file) then -- TODO: Check file extension
                        local fileHash = FS:hashFile(file)
                        local shaderPath = file:gsub(rootPath, tempPath):gsub(".hlsl", fileHash .. ".hlsl")
                        FS:copyFile(file, shaderPath)
                        local shaderName = strsplit(shaderPath, "/")
                        shaderName = shaderName[#shaderName]:gsub(".hlsl", "")
                        shaderName = shaderName .. fileHash
                        loadShaderPostFX(shaderPath, shaderName)
                        table.insert(pack.shaders, {
                            name = shaderName,
                            path = shaderPath,
                            category = "postFx"
                        })
                    end
                end
            end
            LuuksPostFX.shaderPacks[item] = pack
        end
    end

    print("Loaded " .. #LuuksPostFX.shaderPacks .. " shaderpacks!")
end

local function reloadShaders()
    print("Reloading shaders...")

    for i, pack in pairs(LuuksPostFX.shaderPacks) do
        for j, shader in pairs(pack.shaders) do
            local fx = scenetree.findObject("LGM_" .. shader.name .. "_Fx")
            if fx ~= nil then
                fx.isEnabled = false
                fx:delete()
            end
            local shader = scenetree.findObject("LGM_" .. shader.name .. "_ShaderData")
            if shader ~= nil then
                shader:delete()
            end

            -- FS:removeFile(shader.shaderPath) -- TODO: Perhaps only disabling
        end
    end

    loadShaders()
end

removeOldShaders()
loadShaders()

LuuksPostFX.reloadShaders = reloadShaders
LuuksPostFX.updateUniforms = updateUniforms

rawset(_G, "LuuksPostFX", LuuksPostFX)
return LuuksPostFX
