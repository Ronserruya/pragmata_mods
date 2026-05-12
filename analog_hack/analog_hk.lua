local RS_UP_BIT = 0x1000000
local RS_RIGHT_BIT = 0x2000000
local RS_DOWN_BIT = 0x4000000
local RS_LEFT_BIT = 0x8000000
local L1_BIT = 0x100 
local ANY_RS_DIRECTION = RS_UP_BIT | RS_RIGHT_BIT | RS_DOWN_BIT | RS_LEFT_BIT


local clock = sdk.get_managed_singleton("app.GameClock")
local charcterManager = sdk.get_managed_singleton("app.CharacterManager")

local gp_singleton = sdk.get_native_singleton("via.hid.GamePad")
local gp_typedef = sdk.find_type_definition("via.hid.GamePad")

local playerDriver = sdk.find_type_definition("app.PlayerInputDriver")
local puzzleSnake = sdk.find_type_definition("app.PuzzleSnake")

local startMethod = puzzleSnake:get_method("onStartPuzzle()")
local endMethod = puzzleSnake:get_method("onFinishPuzzle()")


local device = sdk.call_native_func(gp_singleton, gp_typedef, "get_MergedDevice")

local last_call_time = 0
local DELAY_MS = 100

local circleBtnID = 0xED094512
local squareBtnID = 0x536D30E2
local triangleBtnID = 0x5757B7C1
local crossBtnID = 0x76B78702

local btnStickMap = {
    [circleBtnID] = RS_RIGHT_BIT,
    [squareBtnID] = RS_LEFT_BIT,
    [triangleBtnID] = RS_UP_BIT,
    [crossBtnID] = RS_DOWN_BIT,
}

local current_buttons = 0
local triggerBtn = 0
local is_hacking = false



sdk.hook(startMethod,
    function(args)
        is_hacking = true
        charcterManager:getPlayerHandle():trgDisablementStatus(0, 16384) -- disable filament cleaner atk
    end
)

sdk.hook(endMethod,
    function(args)
        is_hacking = false
    end
)


sdk.hook(
    playerDriver:get_method("isTrigger"),
    function(args)
        if (not is_hacking) then
            triggerBtn = 0
            return
        end

        triggerBtn = sdk.to_int64(args[3])
        -- local storage = thread.get_hook_storage()
        -- storage["btnID"] = sdk.to_int64(args[3])

    end,
    function(retval)
        -- local storage = thread.get_hook_storage()
        -- local btnID = storage["btnID"]

        if (current_buttons & L1_BIT) ~= 0 then
            local stickBit = btnStickMap[triggerBtn] 
            if (stickBit ~= nil) then
                if (current_buttons & stickBit) ~= 0 then
                    local now = clock:get_SystemElapsedTime()

                    if (now - last_call_time > (DELAY_MS * 1000)) then
                        last_call_time = now
                        return sdk.to_ptr(true)
                    end
                end
            end
        end
            
        return retval
    end
)


re.on_frame(function()
    if (not is_hacking) then
        current_buttons = 0
        return
    end
    charcterManager:getPlayerHandle():trgDisablementStatus(0, 16384) -- disable filament cleaner atk
    
    current_buttons = device:call("get_Button()") or 0
    if (current_buttons & L1_BIT) ~= 0 then
        charcterManager:getPlayerHandle():trgDisablementStatus(4, 16) -- disable camera movment, 4=PUZZLE TYPE, 16=CAMERA STATUS
    end

end)

re.on_draw_ui(function()
    if imgui.tree_node("Analog Stick Hack") then
        local ch, v = imgui.drag_int("Hack speed/delay", DELAY_MS, 10, 50, 400)
        if ch then DELAY_MS = v end
        imgui.tree_pop()
    end
end)


