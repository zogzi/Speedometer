-- Deterministic integration tests for the real client.lua, not a reimplementation.
local now, checks = 0, 0
local tasks, messages, callbacks, commands, api, events = {}, {}, {}, {}, {}, {}
local car = { vehicle = 0, class = 0, driver = 1, dead = false, paused = false,
    speed = 10, velocityY = 10, rpm = 0.52, gear = 3, engine = true,
    health = 1000, lights = 0, beams = 0, fuel = 68 }
local fuelReads, disabled, vehicleReads, speedReads = 0, 0, 0, 0
local pedReads, deathReads, classReads, vectorReads, gearReads = 0, 0, 0, 0, 0
local lightReads, rpmReads = 0, 0
local ui = {}
local safeZone, clockOffset = 0.9, 0

function GetCurrentResourceName() return 'zz-speedomter' end
function SendNUIMessage(message)
    messages[#messages + 1] = message
    if message.action == 'telemetry' then
        for key, value in pairs(message) do if key ~= 'action' then ui[key] = value end end
    end
end
function RegisterNUICallback(name, fn) callbacks[name] = fn end
function RegisterCommand(name, fn) commands[name] = fn end
function RegisterKeyMapping() end
function exports(name, fn) api[name] = fn end
function AddEventHandler(name, fn) events[name] = fn end
function CreateThread(fn) tasks[#tasks + 1] = { co = coroutine.create(fn), due = now } end
function Wait(ms) return coroutine.yield(ms) end
function PlayerPedId() pedReads = pedReads + 1; return 1 end
function GetVehiclePedIsIn() vehicleReads = vehicleReads + 1; return car.vehicle end
function DoesEntityExist(entity) return entity ~= 0 and car.exists ~= false end
function IsEntityDead() deathReads = deathReads + 1; return car.dead end
function GetVehicleClass() classReads = classReads + 1; return car.class end
function GetPedInVehicleSeat() return car.driver end
function IsPauseMenuActive() return car.paused end
function GetGameTimer() return now + clockOffset end
function GetSafeZoneSize() return safeZone end
function GetIsVehicleEngineRunning() return car.engine end
function GetVehicleLightsState() lightReads = lightReads + 1; return true, car.lights, car.beams end
function GetVehicleFuelLevel() fuelReads = fuelReads + 1; return car.fuel end
function GetVehicleEngineHealth() return car.health end
function GetEntitySpeed() speedReads = speedReads + 1; return car.speed end
function GetVehicleCurrentGear() gearReads = gearReads + 1; return car.gear end
local vectorMeta = { __len = function(v) return math.sqrt(v.x*v.x + v.y*v.y + v.z*v.z) end }
function GetEntitySpeedVector()
    vectorReads = vectorReads + 1
    if car.motionVector then return setmetatable(car.motionVector, vectorMeta) end
    -- Keep the scalar magnitude and direction fixture physically consistent.
    local y = math.max(-car.speed, math.min(car.speed, car.velocityY))
    return setmetatable({ x = math.sqrt(math.max(0, car.speed*car.speed-y*y)), y = y, z = 0 }, vectorMeta)
end
function GetVehicleCurrentRpm() rpmReads = rpmReads + 1; return car.rpm end
function DisableControlAction(group, control, disable)
    assert(group == 0 and control == 75 and disable == true, 'exit blocking must use the player control group')
    disabled = disabled + 1
end

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
        nextTask.due = coroutine.status(nextTask.co) == 'dead' and math.huge or now + (delay == 0 and 16 or math.max(1, delay))
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
local defaultInterval = Config.UpdateInterval
check(defaultInterval == 0 and Config.Scale == 0.85, 'shipping defaults prioritize per-frame fluidity and a smaller HUD')
-- Keep the existing 100-ms mode's work-budget/lifecycle coverage, then exercise
-- the new frame-based default separately below. Wait(0) models a 16-ms frame.
Config.UpdateInterval = 100
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
local payload = ui
check(latest('visibility').visible and payload.speed == 36 and payload.rpm == 52
    and payload.gear == '3' and payload.fuel == nil, 'entry sends complete converted telemetry')
check(payload.beltAvailable and payload.belt == false, 'seatbelt begins unfastened in a car')
local sent = count('telemetry')
local reads = fuelReads
local previousSpeedReads, previousRpmReads, previousLightReads = speedReads, rpmReads, lightReads
local previousVectorReads = vectorReads
step(10000)
check(count('telemetry') == sent and fuelReads == 0 and speedReads == previousSpeedReads and vectorReads - previousVectorReads == 100
    and rpmReads - previousRpmReads == 100 and lightReads - previousLightReads == 20,
    'steady driving: one vector read per 100 ms, no redundant speed reads, lights 500 ms, no repeated messages')
car.speed = 20
step(100)
payload = latest('telemetry')
check(payload.speed == 72 and payload.rpm == nil and payload.fuel == nil and payload.gear == nil,
    'a speed-only change sends only speed, without unchanged telemetry fields')
car.speed = 10
step(100)

car.rpm = 0.5213
step(100)
check(math.abs(ui.rpm - 52.13) < .000001, 'small fractional RPM changes reach the smoother without quantization')
car.rpm = 0.527
step(100)
check(math.abs(ui.rpm - 52.7) < .000001, 'RPM retains native precision')
car.rpm = 0.52
step(100)

commands.speedunit(nil, { 'mph' })
step(100)
check(latest('config').unit == 'mph' and math.abs(ui.speed - 22.369362921) < .000001, 'MPH conversion and unit configuration agree')
local configCount = count('config')
commands.speedunit(nil, { 'bad' })
check(count('config') == configCount, 'invalid unit command is ignored')
commands.speedunit(nil, {})
step(100)
check(latest('config').unit == 'kmh' and ui.speed == 36, 'unit toggle restores KM/H')

car.velocityY = -4
step(100)
check(ui.gear == 'R', 'backward motion displays reverse')
car.engine, car.velocityY = false, 0
step(500)
check(ui.gear == 'N' and ui.rpm == 0, 'engine off displays neutral and zero RPM')
car.engine, car.velocityY = true, 10
car.health, car.lights, car.beams, car.fuel = 200, 1, 1, 12
step(500)
payload = ui
check(payload.engineWarning and payload.lights == 2 and payload.fuel == nil, 'damage and high beams are sampled without fuel telemetry')

car.paused = true
step(100)
sent, reads = count('telemetry'), fuelReads
step(500)
check(not latest('visibility').visible and count('telemetry') == sent and fuelReads == reads,
    'pause hides HUD and stops telemetry/status sampling')
car.paused = false
safeZone = 0.8
step(100)
check(latest('visibility').visible and ui.speed == 36, 'resume resends complete telemetry')
check(math.abs(latest('config').safeZone - 0.1) < 0.0001, 'resume refreshes GTA safe-zone placement')

commands.zzbelt()
step(200)
check(api.IsSeatbeltOn() and disabled > 0 and ui.belt, 'belt toggle activates per-frame exit blocking')
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
check(ui.beltAvailable == false and not api.SetSeatbelt(true), 'motorcycles have no seatbelt controls')
car.driver = 2
step(100)
check(not latest('visibility').visible, 'passenger HUD is disabled by default')
car.driver, car.class, car.vehicle = 1, 15, 40
step(750)
check(not latest('visibility').visible, 'aircraft are excluded')
car.class, car.vehicle = 0, 50
local legacyFuelReads = 0
Config.Fuel = { enabled = true, capacity = 100, low = 20 }
Config.ReadFuel = function() legacyFuelReads = legacyFuelReads + 1; error('legacy provider must not run') end
step(1000)
check(latest('visibility').visible and fuelReads == 0 and legacyFuelReads == 0 and ui.fuel == nil,
    'legacy fuel config is ignored: no provider calls, native reads, or fuel packets')
car.health = 999
step(500)
check(ui.engineWarning == true, 'any engine damage below full health raises the damage state')
car.health = 1000
step(500)
check(ui.engineWarning == false, 'repairing the engine clears the damage state')

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
check(ui.speed == 36, 'NUI reload receives a full telemetry refresh')
events.onClientResourceStop('zz-speedomter')
check(not latest('visibility').visible, 'resource stop hides HUD')

-- Fresh instances exercise startup-only config flags without mutating live settings.
local function fresh(configure, vehicleState)
    now, clockOffset = 0, 0
    tasks, messages, callbacks, commands, api, events = {}, {}, {}, {}, {}, {}
    fuelReads, disabled, vehicleReads, speedReads = 0, 0, 0, 0
    pedReads, deathReads, classReads, vectorReads, gearReads = 0, 0, 0, 0, 0
    lightReads, rpmReads, ui = 0, 0, {}
    car = { vehicle = 10, class = 0, driver = 1, dead = false, paused = false,
        speed = 10, velocityY = 10, rpm = 0.52, gear = 3, engine = true,
        health = 1000, lights = 0, beams = 0, fuel = 68 }
    for key, value in pairs(vehicleState or {}) do car[key] = value end
    dofile('config.lua')
    Config.UpdateInterval = 100
    if configure then configure() end
    dofile('client.lua')
    callbacks.ready({}, function() end)
    step(0)
end

fresh(function() Config.Seatbelt.enabled = false end)
check(commands.zzbelt == nil and not api.SetSeatbelt(true) and #tasks == 1
    and ui.beltAvailable == false, 'disabled seatbelt registers no command or frame worker')

fresh(function() Config.Seatbelt.blockExit = false end)
check(api.SetSeatbelt(true), 'belt indicator can operate with exit blocking disabled')
step(500)
check(api.IsSeatbeltOn() and disabled == 0 and #tasks == 1, 'indicator-only belt never starts a frame worker')

fresh()
api.SetSeatbelt(true)
step(16)
local oldPedReads, oldDeathReads, oldVehicleReads, oldDisabled = pedReads, deathReads, vehicleReads, disabled
step(48) -- Between 100-ms main polls: isolates three 16-ms frame-worker iterations.
check(pedReads == oldPedReads and deathReads == oldDeathReads
    and vehicleReads == oldVehicleReads and disabled - oldDisabled == 3,
    'belt worker uses only one native per frame, with no repeated vehicle checks')
car.dead = true
step(100)
check(not api.IsSeatbeltOn() and not latest('visibility').visible,
    'main poll still clears the optimized belt worker on death')

fresh(nil, { speed = 0, velocityY = 0, engine = false })
step(1000)
check(classReads == 1 and vectorReads == 0 and gearReads == 0,
    'parked engine-off vehicle caches class and skips reverse-vector/gear reads')
car.speed, car.velocityY, car.engine = 10, 10, true
step(500)
check(classReads == 1 and vectorReads > 0 and gearReads > 0,
    'moving vehicle resumes gear/vector reads without repeated class queries')

fresh(nil, { speed = 13, velocityY = 4, motionVector = { x = 3, y = 4, z = 12 } })
check(math.abs(ui.speed - 46.8) < .000001 and ui.gear == '3', 'speed includes sideways and vertical motion, not just forward velocity')
local scalarBefore, vectorsBefore = speedReads, vectorReads
step(1000)
check(speedReads == scalarBefore and vectorReads - vectorsBefore == 10,
    'moving vehicles reuse one vector native for speed and reverse each tick')
car.motionVector.y = -4
step(100)
check(math.abs(ui.speed - 46.8) < .000001 and ui.gear == 'R', 'reverse retains full 3D speed magnitude')
car.speed, car.velocityY, car.motionVector = 0, 0, nil
step(100)
scalarBefore, vectorsBefore = speedReads, vectorReads
step(1000)
check(speedReads - scalarBefore == 10 and vectorReads == vectorsBefore and ui.speed == 0,
    'stopping returns to scalar-only sampling on the next tick')
car.speed, car.velocityY = 20, 20
step(100)
check(ui.speed == 72 and vectorReads == vectorsBefore + 1,
    'acceleration is detected at the existing cadence without an extra waiting interval')
car.vehicle, car.speed, car.velocityY = 20, 0, 0
scalarBefore, vectorsBefore = speedReads, vectorReads
step(100)
check(ui.speed == 0 and speedReads == scalarBefore + 1 and vectorReads == vectorsBefore,
    'vehicle changes clear the cached motion state before sampling')

fresh(nil, { dead = true })
car.dead = false
step(750)
check(latest('visibility').visible and classReads == 1,
    'reviving in the same vehicle does not invalidate the class cache')

for _, mode in ipairs({ 0, 1, 2 }) do
    fresh(nil, { lights = mode > 0 and 1 or 0, beams = mode == 2 and 1 or 0 })
    local oldMessages, oldLightReads, oldMotionReads = count('telemetry'), lightReads, vectorReads
    step(2000)
    check(lightReads - oldLightReads == 4 and vectorReads - oldMotionReads == 20
        and count('telemetry') == oldMessages and #tasks == 1,
        'steady light mode ' .. mode .. ' keeps 2-Hz light polling, zero repeated NUI updates, no extra worker')
end

fresh(function() Config.ShowPassenger = true end, { driver = 2 })
check(latest('visibility').visible and ui.speed == 36,
    'passenger option shows the HUD for a non-driver')

fresh(function() Config.HideWhenPaused = false end, { paused = true })
check(latest('visibility').visible, 'pause visibility option is honored')

fresh(function()
    Config.Unit = 'mph'
end, { fuel = 30 })
check(ui.fuel == nil and math.abs(ui.speed - 22.369362921) < .000001
    and latest('config').unit == 'mph', 'initial MPH configuration works without fuel telemetry')

fresh(function() Config.MaxRpm = nil end)
check(latest('config').maxRpm == 9000, 'older configs without MaxRpm receive a safe default dial scale')

fresh(function() Config.RpmInterval = 16 end)
local previousRpmReads = rpmReads
step(1000)
check(rpmReads - previousRpmReads == 10 and #tasks == 1,
    'legacy 16-ms RPM setting cannot re-enable the expensive independent sampler')

fresh()
local beforeMessages = count('telemetry')
for i = 1, 100 do
    car.rpm, car.speed = 0.2 + (i % 70) / 100, i
    step(100)
end
check(rpmReads == 101 and speedReads == 1 and vectorReads == 101 and count('telemetry') - beforeMessages == 100,
    'changing speed and RPM share at most one telemetry packet per 100-ms tick')
car.paused = true
step(100)
previousRpmReads = rpmReads
step(1000)
check(rpmReads == previousRpmReads and #tasks == 1,
    'pause stops RPM sampling without an extra worker')

fresh()
for _ = 1, 100 do api.SetVisible(false); api.SetVisible(true) end
step(100)
check(#tasks == 1, 'rapid hide/show never creates a telemetry worker')
api.SetVisible(false)
previousRpmReads = rpmReads
step(1000)
check(rpmReads == previousRpmReads and #tasks == 1,
    'hidden HUD does not sample RPM')

fresh()
car.exists = false
step(100)
previousRpmReads = rpmReads
check(not latest('visibility').visible, 'invalid vehicle hides without reading its RPM')
car.exists, car.rpm = true, 0.63
step(750)
check(ui.rpm == 63 and rpmReads == previousRpmReads + 1 and #tasks == 1,
    'shared sampler safely recovers after a vehicle temporarily disappears')

fresh(function() Config.UpdateInterval = defaultInterval end)
previousVectorReads, previousRpmReads = vectorReads, rpmReads
local previousPackets = count('telemetry')
for i = 1, 100 do
    car.speed, car.rpm = 10 + i * .001, .52 + i * .00001
    step(16)
end
check(vectorReads - previousVectorReads == 100 and rpmReads - previousRpmReads == 100,
    'default mode samples speed and RPM on every simulated game frame')
check(count('telemetry') - previousPackets == 100 and #tasks == 1,
    'each changed frame sends one combined packet without a separate RPM worker')
check(math.abs(ui.speed - 36.36) < .000001 and math.abs(ui.rpm - 52.1) < .000001,
    'fractional speed and tiny RPM changes survive the complete telemetry path')
car.paused = true
step(16)
local pausedReads, pausedVehicles = rpmReads, vehicleReads
step(1000)
check(rpmReads == pausedReads and vehicleReads - pausedVehicles == 10,
    'frame-based mode backs off to 100-ms vehicle checks while paused')
car.paused = false
step(100)
check(latest('visibility').visible and rpmReads > pausedReads,
    'frame-based telemetry resumes after closing the pause menu')
car.engine = false
step(16)
check(ui.rpm == 0 and ui.gear == 'N', 'engine-off readings reach the frame-based smoother immediately')
api.SetSeatbelt(true)
step(16)
car.vehicle = 20
step(32)
check(not api.IsSeatbeltOn() and coroutine.status(tasks[2].co) == 'dead',
    'vehicle changes clear belt state in frame-based mode')
fresh(function() Config.UpdateInterval = nil; Config.Scale = nil end)
previousRpmReads = rpmReads
step(160)
check(rpmReads - previousRpmReads == 10 and latest('config').scale == .85,
    'missing settings fall back to per-frame sampling and the compact scale')
fresh(function() Config.UpdateInterval = -20 end)
previousRpmReads = rpmReads
step(160)
check(rpmReads - previousRpmReads == 10, 'negative intervals clamp to a game-frame yield')

fresh()
car.exists = false
step(100)
car.exists, car.class = true, 15
step(750)
check(not latest('visibility').visible and classReads == 2,
    'a disappeared entity invalidates its class cache before its handle can be reused')

fresh()
for _ = 1, 200 do
    api.SetSeatbelt(true)
    api.SetSeatbelt(false)
end
step(2)
check(#tasks == 2 and coroutine.status(tasks[2].co) == 'dead' and disabled == 0,
    '200 rapid belt toggle pairs create only one worker, which exits without blocking')
api.SetSeatbelt(true)
step(2)
car.vehicle = 20
local controlsBeforeSwitch = disabled
step(116) -- One 100-ms validation interval plus the next frame-worker yield.
check(not api.IsSeatbeltOn() and disabled - controlsBeforeSwitch <= 7
    and coroutine.status(tasks[3].co) == 'dead', 'shared vehicle poll releases the belt worker by the next frame after validation')
controlsBeforeSwitch = disabled
step(100)
check(disabled == controlsBeforeSwitch, 'no exit suppression remains after the switch is detected')

fresh()
car.health = 200
clockOffset = -1000
step(100)
check(ui.engineWarning == true and lightReads == 2,
    'status polling recovers when the game timer wraps backwards')

fresh()
for i = 1, 1000 do
    car.speed = i % 50
    step(100)
end
check(count('telemetry') == 1001 and #tasks == 1,
    '100-second changing-telemetry simulation produces one packet per tick and no extra workers')

print(string.format('\n%d client checks passed (mocked FiveM natives, actual Lua 5.4).', checks))
