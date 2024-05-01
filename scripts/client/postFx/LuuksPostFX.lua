local LuuksPostFX = {}

local rootPath = "shaderpacks"
local tempPath = "temp/shaders/lgm_tmp"

local totalTime = 0

LuuksPostFX.shaderPacks = {}

-- From: http://lua-users.org/wiki/StringRecipes
local function ends_with(str, ending)
    return ending == "" or str:sub(-#ending) == ending
end

local function enterLoadingScreen()
    core_gamestate.requestEnterLoadingScreen("lgm_LoadingScreen", function() print("LGM Loading Screen Enabled") end)
end

local function exitLoadingScreen()
    core_gamestate.requestExitLoadingScreen("lgm_LoadingScreen")
end

local function forceLightingQuality(level)
    core_settings_graphic:getOptions().GraphicLightingQuality.set(level)
end

local function invalidateShaderCache()
    -- This seems to do nothing
    core_settings_settings.impl.invalidateCache()
end

local function updateEnabledShaders(selectedPack)
    scenetree.findObject("PostEffectCombinePassObject"):setField("enabled", 0, 1)

    for i, pack in pairs(LuuksPostFX.shaderPacks) do
        local enabled = pack.name == selectedPack
        for j, shader in pairs(pack.shaders) do
            local fx = scenetree.findObject("LGM_" .. shader.name .. "_Fx")
            if fx ~= nil then
                fx.isEnabled = enabled
            end
        end

        if enabled then
            if pack.settings.disableDefaultTonemapper then
                scenetree.findObject("PostEffectCombinePassObject"):setField("enabled", 0, 0)
            else
                scenetree.findObject("PostEffectCombinePassObject"):setField("enabled", 0, 1)
            end
        end
    end
end

local function updateUniforms(selectedPack, dt, settingsValues)
    if LuuksPostFX.shaderPacks[selectedPack] == nil then return end

    totalTime = totalTime + dt

    local tod = core_environment.getTimeOfDay()
    local res = core_settings_graphic.selected_resolution

    -- local camForward = core_camera.getForward()
    -- local camPosition = core_camera.getPosition()
    -- camPosition = { x = camPosition.x, y = camPosition.y, z = camPosition.z }
    -- local camFovDeg = core_camera.getFovDeg()

    for i, shader in pairs(LuuksPostFX.shaderPacks[selectedPack].shaders) do
        local fx = scenetree.findObject("LGM_" .. shader.name .. "_Fx")
        if fx then
            fx:setShaderConst("$totalTime", totalTime)
            fx:setShaderConst("$timeOfDay", tod.time)
            fx:setShaderConst("$resolution", res)

            for field, value in pairs(settingsValues[shader.name] or {}) do
                fx:setShaderConst("$" .. field, value)
            end
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

local function loadShaderPostFX(path, name, priority, texPath, textures)
    print("[LGM] Loading " .. name .. " (" .. path .. ")")
    local stateBlock = scenetree.findObject("LGM_" .. name .. "_StateBlock")
    if not stateBlock then
        local pfxDefaultStateBlock = scenetree.findObject("PFX_DefaultStateBlock")
        stateBlock = createObject("GFXStateBlockData")
        stateBlock:inheritParentFields(pfxDefaultStateBlock)
        stateBlock.samplersDefined = true
        stateBlock:setField("samplerStates", 0, "SamplerClampLinear")
        stateBlock:setField("samplerStates", 1, "SamplerClampLinear")
        stateBlock:setField("samplerStates", 2, "SamplerClampLinear")
        stateBlock:setField("samplerStates", 3, "SamplerClampPoint")
        for i, data in pairs(textures) do
            stateBlock:setField("samplerStates", i, "SamplerClampLinear")
        end
        stateBlock:registerObject("LGM_" .. name .. "_StateBlock")
    end

    local shader = scenetree.findObject("LGM_" .. name .. "_ShaderData")
    if not shader then
        shader = createObject("ShaderData")
        shader.DXVertexShaderFile = "shaders/common/postFx/passthruV.hlsl"
        shader.DXPixelShaderFile = path
        shader.pixVersion = 2.0
        shader:registerObject("LGM_" .. name .. "_ShaderData")
    end

    local fx = scenetree.findObject("LGM_" .. name .. "_Fx")
    if not fx then
        fx = createObject("PostEffect")
        fx.isEnabled = false
        fx.allowReflectPass = false
        -- fx:setField("renderTime", 0, "PFXAfterDiffuse")
        fx:setField("renderTime", 0, "PFXBeforeBin")
        fx:setField("renderBin", 0, "AfterPostFX")
        fx.renderPriority = priority

        fx:setField("stateBlock", 0, "LGM_" .. name .. "_StateBlock")

        fx:setField("shader", 0, "LGM_" .. name .. "_ShaderData")
        fx:setField("stateBlock", 0, "PFX_DefaultStateBlock")
        fx:setField("texture", 0, "$backBuffer")
        fx:setField("texture", 1, "#prepass[RT0]")
        fx:setField("texture", 2, "#prepass[Depth]")
        fx:setField("texture", 3, "scripts/client/postFx/rgba_noise_small.dds")

        -- Custom textures
        for i, data in pairs(textures) do
            local path = texPath .. data.path
            fx:setField("texture", data.id, path)
        end

        -- fx:setField("totalTime", 0, 0.0)

        fx:registerObject("LGM_" .. name .. "_Fx")
    end
end

local function loadShaderPack(item)
    local pack = { name = item, shaders = {}, settings = {} }

    -- First we have to load the shaderpack settings file.
    -- Without this file, the shaderpack will not be loaded!
    local packSettingsPath = item .. "/settings.json"
    if FS:fileExists(packSettingsPath) then
        local handle = io.open(packSettingsPath, "r")
        if handle then
            local content = handle:read("*all")
            pack.settings = json.decode(content) -- TODO: If this errors, loading the game breaks entirely. Find a fix for that
            handle:close()
        else
            print("[LGM] The settings file exists, yet can't be opened!")
            return
        end
    else
        print("[LGM] Failed to load shaderpack from " .. item .. " as the settings.json file is missing!")
        return
    end

    local postFxPasses = {}
    local priority = 9999
    for i, pass in pairs(pack.settings.postFx or {}) do
        postFxPasses[pass] = priority
        priority = priority - 1
    end

    if FS:directoryExists(item .. "/postFx") then
        for j, file in pairs(FS:directoryList(item .. "/postFx")) do
            if isFile(file) and ends_with(file, ".hlsl") then
                local shaderName = split(file, "/")
                shaderName = shaderName[#shaderName]:gsub(".hlsl", "")
                local dispName = shaderName

                -- We quickly check if this pass is used, so we can avoid doing
                -- a bunch of extra work, plus we load the priority at the same time
                local priority = postFxPasses[dispName]
                if priority ~= nil then
                    local fileHash = FS:hashFile(file)
                    shaderName = shaderName .. fileHash

                    local settingsPath = file:gsub(".hlsl", ".json")
                    local shaderSettings = {}
                    if FS:fileExists(settingsPath) then
                        -- TODO: Should probably use FS:openFile() but I couldn't quickly figure out what args it wants
                        local handle = io.open(settingsPath, "r")
                        if handle then
                            local content = handle:read("*all")
                            shaderSettings = json.decode(content) -- TODO: If this errors, loading the game breaks entirely. Find a fix for that
                            handle:close(handle)
                        end
                    end

                    local shaderPath = file:gsub(rootPath, tempPath):gsub(".hlsl", fileHash .. ".hlsl")
                    FS:copyFile(file, shaderPath)

                    local texPath = item .. "/"

                    loadShaderPostFX(shaderPath, shaderName, priority, texPath, shaderSettings.textures or {})
                    table.insert(pack.shaders, {
                        name = shaderName,
                        disp = dispName,
                        path = shaderPath,
                        category = "postFx",
                        settings = shaderSettings
                    })
                end
            end
        end
    end
    LuuksPostFX.shaderPacks[item] = pack
end

local function loadShaders()
    print("Loading shaders from " .. rootPath .. "...")
    if not FS:directoryExists(rootPath) then FS:directoryCreate(rootPath) end
    if not FS:directoryExists(tempPath) then FS:directoryCreate(tempPath) end

    LuuksPostFX.shaderPacks = {}

    for i, item in pairs(FS:directoryList(rootPath)) do
        if not isFile(item) then
            loadShaderPack(item)
        end
    end

    print("Loaded " .. #LuuksPostFX.shaderPacks .. " shaderpacks!")
end

local function reloadShadersInternal()
    for i, pack in pairs(LuuksPostFX.shaderPacks) do
        for j, shader in pairs(pack.shaders) do
            local fx = scenetree.findObject("LGM_" .. shader.name .. "_Fx")
            if fx then
                fx.isEnabled = false
                fx:unregisterObject()
                fx:delete()
            end
            local shader = scenetree.findObject("LGM_" .. shader.name .. "_ShaderData")
            if shader then
                shader:unregisterObject()
                shader:delete()
            end
            -- local stateBlock = scenetree.findObject("LGM_" .. shader.name .. "_StateBlock")
            -- if stateBlock then
            --     stateBlock:delete()
            -- end

            -- FS:removeFile(shader.shaderPath)
        end
    end
end

local function reloadShaders()
    print("Reloading shaders...")

    updateEnabledShaders("None")
    reloadShadersInternal()
    loadShaders()
end

removeOldShaders()
loadShaders()

LuuksPostFX.reloadShaders = reloadShaders
LuuksPostFX.updateEnabledShaders = updateEnabledShaders
LuuksPostFX.updateUniforms = updateUniforms

rawset(_G, "LuuksPostFX", LuuksPostFX)
return LuuksPostFX
