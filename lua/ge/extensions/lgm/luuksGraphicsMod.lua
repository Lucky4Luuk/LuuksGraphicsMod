local M = {}

M.dependencies = {"ui_imgui"}
local im = ui_imgui

local showSettings = nil

local selectedPack = settings.getValue("LGM_SelectedPack", "None")

local function createPFX()
    if not LuuksPostFX then
        local pfx = require("/scripts/client/postFx/LuuksPostFX")
    end

    return LuuksPostFX ~= nil
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

        if im.Button("Reload shaderpacks") then
            LuuksPostFX.reloadShaders()
            LuuksPostFX.updateEnabledShaders(selectedPack)
        end
        im.Text("WARNING: If a shader doesn't work properly after\nreloading, please switch shaders, reload shaders again\nand switch back!")

        im.End()
    end
end

local function onUpdate(dt)
    if showSettings == nil then showSettings = im.BoolPtr(false) end
    if worldReadyState == 2 then LuuksPostFX.updateEnabledShaders(selectedPack) end

    LuuksPostFX.updateUniforms(selectedPack, dt)

    drawUI()
end

M.onClientPostStartMission = onClientPostStartMission
M.onUpdate = onUpdate
M.onExtensionLoaded = onExtensionLoaded
M.reloadShaders = function() LuuksPostFX.reloadShaders() end
M.toggleUI = function() if showSettings[0] then showSettings[0] = false else showSettings[0] = true end end

return M
