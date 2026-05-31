local modeManager = sdk.get_managed_singleton("app.MainModeManager")
local enhanceManager = sdk.get_managed_singleton("app.EnhanceManager")
local equipManager = sdk.get_managed_singleton("app.EquipmentPresetManager")
local ckManager = sdk.get_managed_singleton("app.CheckPointManager")
local genWeaponMet = sdk.find_type_definition("app.AcquisitionItemInfo"):get_method("generateNewWeapon")
local inventoryManager = sdk.get_managed_singleton("app.InventoryManager")

local RESPAWN_PHASE = {
    GAME_OVER = 0,
    STARTED = 1,
    GAMEPLAY_STOPPED = 2,
    GAMEPLAY_RESUMED = 3,
    TRAM_TRAVEL = 4,
    TRAVEL_GAMEPLAY_STOPPED = 5,
    READY = 6
}

local currentPhase = RESPAWN_PHASE.READY
loadOutWepIds = {}
local resetWeaponsOnSpawn = true

function equipWeapon(wepId)
    local newWep = genWeaponMet(nil, wepId)
    newWep:add_ref()
    pcall(function() inventoryManager:acquireWeaponItem(newWep._WeaponInfo, nil, nil) end) --pcall since this fails internally but still works overall
end

function isFullLoadout()
    local bp = enhanceManager._EquipmentPerkMainGame._BootingPerks
    local maxCapacity = bp:get_AssaultGadgetCapacity() + bp:get_SupportGadgetCapacity() + bp:get_StrategyGadgetCapacity() + 1
    if (maxCapacity <= 4) then
        return true
    end

    -- if any slot is expended, only return if all 6 weapons are equipped
    local weaponCount = 0
    for _ in pairs(loadOutWepIds) do 
        weaponCount = weaponCount + 1 
    end
    return weaponCount == 6
end

function cleanLoadout()
    slots = inventoryManager:getGadgetSlotHashes()
    slots:add_ref()
    currentGadgets = {}
    for i, s in pairs(slots) do
        s:add_ref()
        currentGadgets[i] = s.m_value
    end
    currentGadgets[0] = nil -- dont clear the main pistol/rifle

    for i, s in pairs(currentGadgets) do
        inventoryManager:unequipGadget(s)
        inventoryManager:removeGadget(s)
    end
end

function resetLoadout()
    for i, s in pairs(loadOutWepIds) do
        if (s~=775612873 and s~=1028629837) then -- basic pistol/rifle
            equipWeapon(s)
        end
    end
    equipManager._CurrentControlPreset._ActiveSkillPreset:apply()
end

function wrapToLastCheckpoint()
    local gid = sdk.find_type_definition("System.Guid"):create_instance()
    local lastCheckpoint = ckManager:getLastAccessCheckPointInfo()
    ckManager:warpCheckPoint(lastCheckpoint, lastCheckpoint, gid)
end



sdk.hook(sdk.find_type_definition("app.EquipmentPresetManager.Preset"):get_method("applyToCurrentEquipment"),
    function(args)
        local preset = sdk.to_managed_object(args[2])
        local slots = preset._WeaponPreset._Slots
        loadOutWepIds = {}
        for i=0, slots._size - 1 do
            loadOutWepIds[i] = slots[i]._Id
        end
    end
)


sdk.hook(sdk.find_type_definition("app.GameOverManager"):get_method("requestDisplayGameOverGUI"),
    function(args)
        currentPhase = RESPAWN_PHASE.GAME_OVER
    end
)

sdk.hook(sdk.find_type_definition("app.InGameMode"):get_method("restart"),
    function(args)
        if (currentPhase == RESPAWN_PHASE.GAME_OVER) then
            local tranision = sdk.to_managed_object(args[3])
            if (tranision:get_IsTransitionBasement() and not tranision:get_IsTransitionFromMissionMode()) then 
                currentPhase = RESPAWN_PHASE.STARTED
            else
                currentPhase = RESPAWN_PHASE.READY
            end
        end
    end
)


re.on_frame(function()
    if (currentPhase == RESPAWN_PHASE.READY) then
        return
    end

    local isInGameplay = modeManager:get_IsInGamePlay()

    if (currentPhase == RESPAWN_PHASE.STARTED) then
        if (not isInGameplay) then
            currentPhase = RESPAWN_PHASE.GAMEPLAY_STOPPED
        end
    elseif (currentPhase == RESPAWN_PHASE.GAMEPLAY_STOPPED) then
        if (isInGameplay) then
            currentPhase = RESPAWN_PHASE.GAMEPLAY_RESUMED
        end
    elseif (currentPhase == RESPAWN_PHASE.GAMEPLAY_RESUMED) then
        currentPhase = RESPAWN_PHASE.TRAM_TRAVEL
        wrapToLastCheckpoint()
    elseif (currentPhase == RESPAWN_PHASE.TRAM_TRAVEL) then
        if (not isInGameplay) then
            currentPhase = RESPAWN_PHASE.TRAVEL_GAMEPLAY_STOPPED
        end
    elseif (currentPhase == RESPAWN_PHASE.TRAVEL_GAMEPLAY_STOPPED) then
        if (isInGameplay) then
            currentPhase = RESPAWN_PHASE.READY
            if (resetWeaponsOnSpawn and isFullLoadout()) then
                cleanLoadout()
                resetLoadout()
            end
            
        end
    end
end)

re.on_draw_ui(function()
    if imgui.tree_node("[Respawn at checkpoint]") then 
        local changed, value = imgui.checkbox("Reset weapons on spawn?", resetWeaponsOnSpawn)
        if changed then
            resetWeaponsOnSpawn = value
        end
        
        imgui.tree_pop() 
    end
end)
