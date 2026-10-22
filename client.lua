local RESOURCE = GetCurrentResourceName()
local visible, nuiReady, suppressed = false, false, false
local currentVehicle, beltVehicle = 0, 0
local observedVehicle, vehicleClass = 0, -1
local belted, beltAvailable = false, false
local beltThreadRunning = false
local lastPayload, lastStatusAt = {}, 0
local unit = Config.Unit == 'mph' and 'mph' or 'kmh'
local interval = math.max(50, tonumber(Config.UpdateInterval) or 100)
local idleInterval = math.max(interval, tonumber(Config.IdleInterval) or 750)
local statusInterval = math.max(interval, tonumber(Config.StatusInterval) or 500)
local status = {}
local payload = {} -- reuse the telemetry buffer instead of allocating one every tick

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function setVisible(value)
    if visible ~= value then
        visible = value
        SendNUIMessage({ action = 'visibility', visible = value })
        if not value then lastPayload = {} end
    end
end

local function resetBelt()
    belted, beltAvailable, beltVehicle = false, false, 0
end

local function setBelt(value)
    if not beltAvailable or not DoesEntityExist(beltVehicle) then return false end
    local ped = PlayerPedId()
    if GetVehiclePedIsIn(ped, false) ~= beltVehicle or IsEntityDead(ped)
        or (not Config.ShowPassenger and GetPedInVehicleSeat(beltVehicle, -1) ~= ped) then
        resetBelt()
        return false
    end
    belted = value == true
    -- Exit-control natives last one frame. Create this worker on demand, so it
    -- consumes no idle ticks at all when unbelted or outside a vehicle.
    if belted and Config.Seatbelt.blockExit and not beltThreadRunning then
        beltThreadRunning = true
        CreateThread(function()
            while belted and beltVehicle ~= 0 do
                -- Only the frame-scoped native belongs here. Vehicle, seat,
                -- death and exit validation run in the shared vehicle poll.
                DisableControlAction(0, 75, true)
                Wait(0)
            end
            beltThreadRunning = false
        end)
    end
    return true
end

local function sendConfig()
    local safeZone = clamp(GetSafeZoneSize(), 0.8, 1.0)
    SendNUIMessage({
        action = 'config',
        unit = unit,
        scale = clamp(tonumber(Config.Scale) or 1, 0.65, 1.5),
        right = math.max(0, tonumber(Config.Position.right) or 32),
        bottom = math.max(0, tonumber(Config.Position.bottom) or 28),
        safeZone = (1 - safeZone) / 2,
        accent = Config.Accent,
        maxRpm = tonumber(Config.MaxRpm) or 9000
    })
end

RegisterNUICallback('ready', function(_, cb)
    nuiReady = true
    lastPayload = {}
    sendConfig()
    -- A reloaded NUI must receive visibility even if Lua's state has not changed.
    SendNUIMessage({ action = 'visibility', visible = visible })
    cb({ ok = true })
end)

RegisterCommand('speedunit', function(_, args)
    local requested = args[1] and args[1]:lower()
    if requested and requested ~= 'mph' and requested ~= 'kmh' then return end
    unit = requested or (unit == 'kmh' and 'mph' or 'kmh')
    lastPayload = {}
    sendConfig()
end, false)

if Config.Seatbelt.enabled then
    RegisterCommand('zzbelt', function()
        setBelt(not belted)
    end, false)
    RegisterKeyMapping('zzbelt', 'zz-speedomter: toggle seatbelt', 'keyboard', Config.Seatbelt.key)
end

-- Optional integrations for another HUD/menu or seatbelt resource.
exports('SetVisible', function(value)
    suppressed = value == false
    if suppressed then setVisible(false) end
end)
exports('SetSeatbelt', setBelt)
exports('IsSeatbeltOn', function() return belted end)

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)
        local exists = vehicle ~= 0 and DoesEntityExist(vehicle)
        -- Vehicle class is fixed for an entity; do not query it every sample.
        if vehicle ~= observedVehicle then
            observedVehicle = vehicle
            vehicleClass = -1
        end
        if exists and vehicleClass == -1 then vehicleClass = GetVehicleClass(vehicle) end
        local class = vehicleClass
        local eligible = exists and not IsEntityDead(ped) and Config.Classes[class] == true
            and (Config.ShowPassenger or GetPedInVehicleSeat(vehicle, -1) == ped)

        local nextVehicle = eligible and vehicle or 0
        if nextVehicle ~= currentVehicle then
            resetBelt()
            currentVehicle = nextVehicle
            lastPayload, status, lastStatusAt = {}, {}, 0
        end

        if eligible then
            beltAvailable = Config.Seatbelt.enabled
                and not Config.Seatbelt.excludedClasses[class]
            beltVehicle = beltAvailable and vehicle or 0
        end

        local shouldShow = eligible and nuiReady and not suppressed
            and not (Config.HideWhenPaused and IsPauseMenuActive())
        -- Refresh placement after the player edits GTA's safe-zone in the pause menu.
        if shouldShow and not visible then sendConfig() end
        setVisible(shouldShow)

        if shouldShow then
            local now = GetGameTimer()
            status.engine = GetIsVehicleEngineRunning(vehicle)
            if status.engineWarning == nil or now < lastStatusAt or now - lastStatusAt >= statusInterval then
                local _, lights, highBeams = GetVehicleLightsState(vehicle)
                status.engineWarning = GetVehicleEngineHealth(vehicle) < 1000
                status.lights = highBeams == 1 and 2 or (lights == 1 and 1 or 0)
                lastStatusAt = now
            end

            local speed = GetEntitySpeed(vehicle)
            local gear = status.engine and GetVehicleCurrentGear(vehicle) or 0
            local reversing = speed > 0.5 and GetEntitySpeedVector(vehicle, true).y < -0.5
            -- Half-percent detail avoids sending idle RPM jitter. Interpolation
            -- stays in the browser; RPM shares one packet with speed and gear.
            payload.rpm = status.engine
                and math.floor(clamp(GetVehicleCurrentRpm(vehicle), 0, 1) * 200 + 0.5) / 2 or 0
            payload.speed = math.floor(speed * (unit == 'mph' and 2.2369362921 or 3.6) + 0.5)
            payload.gear = reversing and 'R' or ((not status.engine or gear == 0) and 'N' or tostring(gear))
            payload.engine = status.engine
            payload.engineWarning = status.engineWarning
            payload.lights = status.lights
            payload.belt = belted
            payload.beltAvailable = beltAvailable
            -- Send deltas only; a stationary car generates no repeated NUI updates.
            local delta
            for key, value in pairs(payload) do
                if lastPayload[key] ~= value then
                    delta = delta or { action = 'telemetry' }
                    delta[key] = value
                    lastPayload[key] = value
                end
            end
            if delta then SendNUIMessage(delta) end
        end
        Wait(eligible and interval or idleInterval)
    end
end)

AddEventHandler('onClientResourceStop', function(name)
    if name ~= RESOURCE then return end
    resetBelt()
    setVisible(false)
end)
