Config = {}

Config.Unit = 'kmh' -- 'kmh' or 'mph'; /speedunit switches locally for this session
Config.Scale = 1.0 -- 0.65–1.5
Config.Position = { right = 32, bottom = 28 } -- pixels, before game safe-zone inset
Config.Accent = '#62f5bb'
Config.MaxRpm = 9000 -- visual estimate; GTA exposes normalized RPM, not real engine RPM
Config.ShowPassenger = false
Config.HideWhenPaused = true

Config.UpdateInterval = 100 -- milliseconds while driving (minimum 50)
Config.IdleInterval = 750 -- milliseconds outside supported vehicles
Config.StatusInterval = 500 -- fuel, engine health and lights polling

-- Road vehicles only. Add/remove GTA vehicle classes here.
Config.Classes = {
    [0] = true, [1] = true, [2] = true, [3] = true, [4] = true,
    [5] = true, [6] = true, [7] = true, [8] = true, [9] = true,
    [10] = true, [11] = true, [12] = true, [17] = true,
    [18] = true, [19] = true, [20] = true, [22] = true
}

Config.Fuel = {
    enabled = true,
    capacity = 100, -- native fuel level is usually 0–100; change for custom providers
    low = 20 -- percent
}

-- Replace this function if your fuel resource does not synchronize native fuel.
-- Example: return exports['LegacyFuel']:GetFuel(vehicle)
Config.ReadFuel = function(vehicle)
    return GetVehicleFuelLevel(vehicle)
end

Config.Seatbelt = {
    enabled = true, -- disable if another resource already handles seatbelts
    key = 'B', -- users can remap in Settings > Key Bindings > FiveM
    blockExit = true, -- prevents normal exit while belted; does not implement crash ejection
    excludedClasses = { [8] = true, [13] = true }
}
