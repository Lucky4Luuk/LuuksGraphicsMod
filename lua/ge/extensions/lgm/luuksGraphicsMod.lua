local M = {}

M.dependencies = {"ui_imgui"}
local im = ui_imgui

local showSettings = nil

local selectedPack = settings.getValue("LGM_SelectedPack", "None")
local settingsValues = {}

local function createPFX()
    if not LuuksPostFX then
        local pfx = require("/scripts/client/postFx/LuuksPostFX")
    end

    return LuuksPostFX ~= nil
end

local function setDefaultSettings()
    local pack = LuuksPostFX.shaderPacks[selectedPack] or { shaders = {} }
    for i, shader in pairs(pack.shaders) do
        local shaderSettings = shader.settings or {}
        if shaderSettings.fields ~= nil then
            settingsValues[shader.name] = settingsValues[shader.name] or {}
            for field, fieldData in pairs(shaderSettings.fields) do
                local default = fieldData.default or (fieldData.min + fieldData.max) / 2
                settingsValues[shader.name][field] = settingsValues[shader.name][field] or default
            end
        end
    end
end

local function onClientPostStartMission()
    createPFX()
end

local function onExtensionLoaded()
    log("I", "", "Luuks Graphics Mod extension loaded!")
end

local function drawUI()
    if not showSettings[0] then return end

    if im.Begin("Luuks Graphics Mod - Settings", showSettings, im.WindowFlags_AlwaysAutoResize) then
        if im.BeginCombo("Shaderpack", selectedPack) then
            local function drawPackItem(name)
                local isSelected = selectedPack == name
                if im.Selectable1(name, isSelected) then
                    selectedPack = name
                    LuuksPostFX.updateEnabledShaders(selectedPack)
                    setDefaultSettings()
                    settings.setValue("LGM_SelectedPack", selectedPack)
                    settings.save()
                else
                    im.SetItemDefaultFocus()
                end
            end

            drawPackItem("None")
            for i, pack in pairs(LuuksPostFX.shaderPacks) do
                drawPackItem(pack.name)
            end

            im.EndCombo()
        end
        im.Separator()

        -- Draw settings
        local pack = LuuksPostFX.shaderPacks[selectedPack] or { shaders = {} }
        for i, shader in pairs(pack.shaders) do
            im.Text(shader.disp)
            local shaderSettings = shader.settings or {}
            if shaderSettings.fields ~= nil then
                settingsValues[shader.name] = settingsValues[shader.name] or {}
                for field, fieldData in pairs(shaderSettings.fields) do
                    local default = fieldData.default or (fieldData.min + fieldData.max) / 2
                    settingsValues[shader.name][field] = settingsValues[shader.name][field] or default
                    local ptr = im.FloatPtr(settingsValues[shader.name][field])
                    if im.SliderFloat(fieldData.disp, ptr, fieldData.min, fieldData.max) then
                        settingsValues[shader.name][field] = ptr[0]
                    end
                end
            end
            im.Separator()
        end
        if #(pack.shaders) == 0 then im.Separator() end

        if im.Button("Reload shaderpacks") then
            LuuksPostFX.reloadShaders()
            LuuksPostFX.updateEnabledShaders(selectedPack)
        end
        im.Text("WARNING: If a shader doesn't work properly after\nreloading, please switch shaders, reload shaders again\nand switch back!")

        im.End()
    end
end

local function onUpdate(dt)
    if not LuuksPostFX then return end

    if showSettings == nil then showSettings = im.BoolPtr(false) end
    if worldReadyState == 2 then
        LuuksPostFX.updateEnabledShaders(selectedPack)
        setDefaultSettings()
    end

    LuuksPostFX.updateUniforms(selectedPack, dt, settingsValues)

    drawUI()
end

M.onClientPostStartMission = onClientPostStartMission
M.onUpdate = onUpdate
M.onExtensionLoaded = onExtensionLoaded
M.reloadShaders = function() LuuksPostFX.reloadShaders() end
M.toggleUI = function() if showSettings[0] then showSettings[0] = false else showSettings[0] = true end end

return M
