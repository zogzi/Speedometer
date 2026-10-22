Config = {}

Config.Unit = 'kmh' -- 'kmh' or 'mph'; /speedunit switches locally for this session
Config.Scale = 0.85 -- 0.65–1.5; default footprint: 306 × 272 pixels
Config.Position = { right = 32, bottom = 28 } -- pixels, before game safe-zone inset
Config.Accent = '#e7edf0'
Config.MaxRpm = 9000 -- visual dial scale; GTA provides normalized RPM, not real RPM
Config.ShowPassenger = false
Config.HideWhenPaused = true

Config.UpdateInterval = 0 -- 0 = every game frame for maximum fluidity; 100 = lower-cost sampling
Config.IdleInterval = 750 -- milliseconds outside supported vehicles
Config.StatusInterval = 500 -- engine health and lights polling

-- Road vehicles only. Add/remove GTA vehicle classes here.
Config.Classes = {
    [0] = true, [1] = true, [2] = true, [3] = true, [4] = true,
    [5] = true, [6] = true, [7] = true, [8] = true, [9] = true,
    [10] = true, [11] = true, [12] = true, [17] = true,
    [18] = true, [19] = true, [20] = true, [22] = true
}

Config.Seatbelt = {
    enabled = true, -- disable if another resource already handles seatbelts
    key = 'B', -- users can remap in Settings > Key Bindings > FiveM
    blockExit = true, -- prevents normal exit while belted; does not implement crash ejection
    excludedClasses = { [8] = true, [13] = true }
}
