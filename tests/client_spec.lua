-- Deterministic integration tests for the real client.lua, not a reimplementation.
local now, checks = 0, 0
local tasks, messages, callbacks, commands, api, events = {}, {}, {}, {}, {}, {}
local car = { vehicle = 0, class = 0, driver = 1, dead = false, paused = false,
    speed = 10, velocityY = 10, rpm = 0.52, gear = 3, engine = true,
    health = 1000, lights = 0, beams = 0, fuel = 68 }
local fuelReads, disabled, vehicleReads, speedReads = 0, 0, 0, 0
local safeZone = 0.9

function GetCurrentResourceName() return 'zz-speedomter' end
function SendNUIMessage(message) messages[#messages + 1] = message end
function RegisterNUICallback(name, fn) callbacks[name] = fn end
function RegisterCommand(name, fn) commands[name] = fn end
function RegisterKeyMapping() end
function exports(name, fn) api[name] = fn end
function AddEventHandler(name, fn) events[name] = fn end
function CreateThread(fn) tasks[#tasks + 1] = { co = coroutine.create(fn), due = now } end
function Wait(ms) return coroutine.yield(ms) end
function PlayerPedId() return 1 end
function GetVehiclePedIsIn() vehicleReads = vehicleReads + 1; return car.vehicle end
function DoesEntityExist(entity) return entity ~= 0 end
function IsEntityDead() return car.dead end
function GetVehicleClass() return car.class end
function GetPedInVehicleSeat() return car.driver end
function IsPauseMenuActive() return car.paused end
function GetGameTimer() return now end
function GetSafeZoneSize() return safeZone end
function GetIsVehicleEngineRunning() return car.engine end
function GetVehicleLightsState() return true, car.lights, car.beams end
function GetVehicleFuelLevel() fuelReads = fuelReads + 1; return car.fuel end
function GetVehicleEngineHealth() return car.health end
function GetEntitySpeed() speedReads = speedReads + 1; return car.speed end
function GetVehicleCurrentGear() return car.gear end
function GetEntitySpeedVector() return { y = car.velocityY } end
function GetVehicleCurrentRpm() return car.rpm end
function DisableControlAction() disabled = disabled + 1 end

local function step(duration)
    local target = now + duration
    while true do
        local nextTask
        for _, task in ipairs(tasks) do
            if task.due <= target and (not nextTask or task.due < nextTask.due) then nextTask = task end
        end
        if not nextTask then break end
        now = nextTask.due
        local ok, delay = coroutine.resume(nextTask.co)
        assert(ok, delay)
        nextTask.due = coroutine.status(nextTask.co) == 'dead' and math.huge or now + math.max(1, delay)
    end
    now = target
end

local function check(condition, name)
    assert(condition, name)
    checks = checks + 1
    print('PASS ' .. name)
end

local function latest(action)
    for i = #messages, 1, -1 do if messages[i].action == action then return messages[i] end end
    return {}
end

local function count(action)
    local result = 0
    for _, message in ipairs(messages) do if message.action == action then result = result + 1 end end
    return result
end

assert(loadfile('fxmanifest.lua')) -- parse the manifest as Lua without invoking its DSL
dofile('config.lua')
dofile('client.lua')

step(0)
check(#messages == 0, 'no telemetry or visible HUD before NUI readiness')
local acknowledged = false
callbacks.ready({}, function(reply) acknowledged = reply.ok end)
check(acknowledged and latest('config').unit == 'kmh' and latest('visibility').visible == false,
    'NUI handshake supplies configuration and hidden state')
step(1500)
check(count('telemetry') == 0 and disabled == 0 and fuelReads == 0 and #tasks == 1,
    'no vehicle work or idle seatbelt thread on foot')
local previousVehicleReads = vehicleReads
step(7500)
check(vehicleReads - previousVehicleReads == 10 and speedReads == 0,
    'on-foot vehicle detection runs once per 750 ms, with zero speed reads')

car.vehicle = 10
step(750)
local payload = latest('telemetry')
check(latest('visibility').visible and payload.speed == 36 and payload.rpm == 52
    and payload.gear == '3' and payload.fuel == 68, 'entry sends complete converted telemetry')
check(payload.beltAvailable and payload.belt == false, 'seatbelt begins unfastened in a car')
local sent = count('telemetry')
local reads = fuelReads
local previousSpeedReads = speedReads
step(10000)
check(count('telemetry') == sent and fuelReads - reads == 20 and speedReads - previousSpeedReads == 100,
    '10-second steady state: zero NUI packets, 100 speed reads, 20 fuel reads')
car.speed = 20
step(100)
payload = latest('telemetry')
check(payload.speed == 72 and payload.rpm == nil and payload.fuel == nil and payload.gear == nil,
    'a speed-only change sends only speed, without unchanged telemetry fields')
car.speed = 10
step(100)

commands.speedunit(nil, { 'mph' })
step(100)
check(latest('config').unit == 'mph' and latest('telemetry').speed == 22, 'MPH conversion and unit configuration agree')
local configCount = count('config')
commands.speedunit(nil, { 'bad' })
check(count('config') == configCount, 'invalid unit command is ignored')
commands.speedunit(nil, {})
step(100)
check(latest('config').unit == 'kmh' and latest('telemetry').speed == 36, 'unit toggle restores KM/H')

car.velocityY = -4
step(100)
check(latest('telemetry').gear == 'R', 'backward motion displays reverse')
car.engine, car.velocityY = false, 0
step(500)
check(latest('telemetry').gear == 'N' and latest('telemetry').rpm == 0, 'engine off displays neutral and zero RPM')
car.engine, car.velocityY = true, 10
car.health, car.lights, car.beams, car.fuel = 200, 1, 1, 12
step(500)
payload = latest('telemetry')
check(payload.engineWarning and payload.lights == 2 and payload.fuel == 12, 'damage, high beams and low fuel are sampled')

car.paused = true
step(100)
sent, reads = count('telemetry'), fuelReads
step(500)
check(not latest('visibility').visible and count('telemetry') == sent and fuelReads == reads,
    'pause hides HUD and stops telemetry/status sampling')
car.paused = false
safeZone = 0.8
step(100)
check(latest('visibility').visible and latest('telemetry').speed == 36, 'resume resends complete telemetry')
check(math.abs(latest('config').safeZone - 0.1) < 0.0001, 'resume refreshes GTA safe-zone placement')

commands.zzbelt()
step(200)
check(api.IsSeatbeltOn() and disabled > 0 and latest('telemetry').belt, 'belt toggle activates per-frame exit blocking')
commands.zzbelt()
step(100)
local disabledBefore = disabled
step(300)
check(not api.IsSeatbeltOn() and disabled == disabledBefore, 'unfastening stops exit suppression')
check(api.SetSeatbelt(true), 'seatbelt integration accepts a supported vehicle')
car.vehicle = 20
step(100)
check(not api.IsSeatbeltOn(), 'changing vehicles clears belt state')

api.SetVisible(false)
sent = count('telemetry')
step(200)
check(not latest('visibility').visible and count('telemetry') == sent, 'integration can suppress HUD immediately')
api.SetVisible(true)
step(100)
check(latest('visibility').visible, 'integration restores automatic visibility')

car.class, car.vehicle = 8, 30
step(100)
check(latest('telemetry').beltAvailable == false and not api.SetSeatbelt(true), 'motorcycles have no seatbelt controls')
car.driver = 2
step(100)
check(not latest('visibility').visible, 'passenger HUD is disabled by default')
car.driver, car.class = 1, 15
step(750)
check(not latest('visibility').visible, 'aircraft are excluded')
car.class = 0
Config.ReadFuel = function() error('provider unavailable') end
step(750)
check(latest('visibility').visible and latest('telemetry').fuel == -1, 'fuel provider failure remains unknown without breaking HUD')
Config.ReadFuel = function() return 0 / 0 end
step(500)
check(latest('telemetry').fuel == -1, 'NaN fuel is handled as unknown')
Config.ReadFuel = function() return math.huge end
step(500)
check(latest('telemetry').fuel == -1, 'infinite fuel is handled as unknown')
Config.ReadFuel = function(vehicle) return GetVehicleFuelLevel(vehicle) end
car.fuel = 999
step(500)
check(latest('telemetry').fuel == 100, 'fuel is clamped to a full tank')
Config.Fuel.enabled = false
reads = fuelReads
step(1000)
check(fuelReads == reads, 'disabled fuel is not polled')

car.dead = true
step(100)
check(not latest('visibility').visible and not api.IsSeatbeltOn(), 'death hides HUD and resets belt')
car.dead, car.vehicle = false, 0
check(not api.SetSeatbelt(true), 'seatbelt export rejects exit immediately, before the next vehicle poll')
step(750)
check(not latest('visibility').visible and not api.SetSeatbelt(true), 'exit hides HUD and rejects stale belt state')
car.vehicle = 10
step(750)
callbacks.ready({}, function() end)
check(latest('visibility').visible and latest('config').unit == 'kmh', 'NUI reload restores current configuration and visibility')
step(100)
check(latest('telemetry').speed == 36, 'NUI reload receives a full telemetry refresh')
events.onClientResourceStop('zz-speedomter')
check(not latest('visibility').visible, 'resource stop hides HUD')

print(string.format('\n%d client checks passed (mocked FiveM natives, actual Lua 5.4).', checks))
