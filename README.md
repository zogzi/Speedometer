# zz-speedomter

A standalone, Forza-inspired FiveM vehicle HUD. No ESX, QBCore, database, npm build, CDN, custom fonts, or server-side scripts required. All UI assets ship with the resource.

![zz-speedomter browser preview](docs/preview.png)

See [INSTALL.md](INSTALL.md) for the step-by-step server owner's guide and [PERFORMANCE.md](PERFORMANCE.md) for the local optimization and visual review, including what still needs in-game validation.

## Install

If downloading this repository through **Code → Download ZIP**, rename the extracted `Speedometer-main` folder to `zz-speedomter` before installing it.

1. Copy this resource into `resources/[local]/zz-speedomter/`. `fxmanifest.lua` must be directly inside that folder, not another nested folder.
2. Add this line to `server.cfg`:

   ```cfg
   ensure zz-speedomter
   ```

3. Restart your server, or run `refresh` then `ensure zz-speedomter` from the server console. Enter the driver's seat of a road vehicle.

The folder may have another name; use that name in `ensure` and in integration exports. Disable any existing speedometer to avoid overlapping HUDs. GTA's original HUD is left intact.

## Included

- Digital speed, KM/H or MPH, gear, reverse detection, and normalized RPM arc with a redline state.
- Native fuel level, low-fuel warning, engine damage warning, headlights and high-beam indicators.
- Optional seatbelt toggle with exit blocking. Bikes have no belt indicator.
- Driver-only display by default; hides on foot, on death, in unsupported vehicle classes, and in the pause menu.
- Safe-zone-aware placement, configurable size and accent color, transparent NUI, and no input focus capture.

Edit `config.lua` and restart the resource to apply configuration changes:

| Option | Default | Purpose |
| --- | --- | --- |
| `Unit` | `'kmh'` | Initial speed units |
| `Scale` | `1.0` | HUD size, clamped to 0.65–1.5 |
| `Position` | right 32, bottom 28 | Pixel offset, plus GTA safe-zone inset |
| `Accent` | `'#62f5bb'` | Six-digit hex accent color |
| `MaxRpm` | `9000` | Dial scale, not an engine tuning value |
| `ShowPassenger` | `false` | Also display for passengers |
| `HideWhenPaused` | `true` | Hide when the pause menu is open |
| `UpdateInterval` | `100` | Active telemetry interval in milliseconds; minimum 50 |
| `IdleInterval` | `750` | Vehicle detection interval on foot |
| `StatusInterval` | `500` | Fuel, engine status, and light polling interval |
| `Classes` | Road classes | Eligible GTA vehicle classes |
| `Fuel.enabled` | `true` | Show the fuel meter |
| `Fuel.capacity` | `100` | Provider's full-tank value, normalized into percent |
| `Fuel.low` | `20` | Low-fuel warning threshold in percent |
| `Seatbelt.enabled` | `true` | Register belt control and show belt status |
| `Seatbelt.key` | `'B'` | Default key binding |
| `Seatbelt.blockExit` | `true` | Block normal exit while belted |

`/speedunit` toggles units; `/speedunit mph` and `/speedunit kmh` select explicitly. This choice lasts for the client session. **B** or `/zzbelt` toggles the belt. Players can remap the key under **Settings → Key Bindings → FiveM → zz-speedomter: toggle seatbelt**. Existing user mappings take precedence over a changed default.

The seatbelt feature blocks normal vehicle exit only. It does **not** change crash physics, implement ejection, provide damage protection, or make passengers invulnerable. Belt state resets on vehicle change, exit, or death. If another resource manages seatbelts, set `Config.Seatbelt.enabled = false` to avoid conflicting controls.

GTA supplies normalized RPM, so the numeric RPM display is a visual estimate based on `MaxRpm`. Neutral is shown when the engine is off or the native gear is zero; reverse is detected from backward motion. This is not a transmission simulation. Boats, aircraft, bicycles, and trains are excluded by default.

## Fuel integration

The default `Config.ReadFuel(vehicle)` reads `GetVehicleFuelLevel`. It does not consume or alter fuel. Resources that synchronize the native fuel level work without changes. For a different provider, replace **only this function in `config.lua`**, for example:

```lua
Config.ReadFuel = function(vehicle)
    return exports['LegacyFuel']:GetFuel(vehicle)
end
```

Start that provider before this HUD. Set `Config.Fuel.capacity` to its full-tank value. The function runs at the slower status interval and should not yield. Errors or nonnumeric results display `—`, not an empty tank. Fuel is not polled when its meter is disabled.

## Optional client integrations

These exports are client-side; replace `zz-speedomter` if you renamed the folder:

```lua
exports['zz-speedomter']:SetVisible(false) -- suppress, e.g. for a cinematic menu
exports['zz-speedomter']:SetVisible(true)  -- allow automatic vehicle visibility again

local success = exports['zz-speedomter']:SetSeatbelt(true)
local belted = exports['zz-speedomter']:IsSeatbeltOn()
```

`SetVisible(true)` does not force the HUD onto the screen outside eligible vehicles. `SetSeatbelt` returns false until the player is in an eligible vehicle with the belt feature enabled. The configured key still toggles the belt when using this export.

## Performance and validation

The client polls telemetry at 10 Hz by default, rounds speed and RPM, and sends only changed fields to NUI. Telemetry and status buffers are reused; message objects are created only when data changes. Fuel, engine health, and lights are read at 2 Hz. On foot, the main loop sleeps for 750 ms. The browser has no animation loop, polling timer, or network dependency during normal gameplay. SVG ticks are constructed once and only rebuilt if the RPM scale changes. A frame loop is necessary **only while belted with exit blocking enabled**, because FiveM control suppression lasts one frame.

No `0.00 ms` or fixed FPS claim is made. Actual CPU usage depends on your server, hardware, frame rate, and other resources. Use `resmon 1` in FiveM to check this resource on foot, driving, and belted. Lower `UpdateInterval` values increase native calls and NUI traffic.

### Browser preview

Open `web/index.html?preview` in a browser, or serve the `web` folder with any static server and append `?preview` to its address. The preview includes cruise/redline/parked presets, speed and RPM sliders, and unit/belt/light controls. Its presentation and controls never appear inside FiveM. Opening the page without `?preview` keeps the HUD hidden until game messages arrive.

### Automated checks

Runtime deployment needs only the files listed in `fxmanifest.lua`. Run the following development checks from the repository checkout; the deployment ZIP omits the `tests` directory:

```sh
node --check web/app.js
lua5.4 tests/client_spec.lua
# Alternative on Linux with Python and liblua5.4 installed:
python tests/run_lua_tests.py

# Requires Python Playwright and Chromium for development only:
python tests/test_ui.py
```

Lua tests exercise the actual client code with a deterministic scheduler and mocked FiveM natives. Browser tests exercise the real page and NUI message protocol in Chromium. They cannot replace in-game native integration or resource profiling.

### FiveM acceptance check

1. `ensure zz-speedomter`; verify no errors in the client F8 console.
2. Enter a car, accelerate, brake, reverse, and switch units. Verify speed, gear, and RPM changes.
3. Toggle headlights/high beams, inspect fuel, toggle the belt and try exiting. Unbelt and exit; verify the HUD hides.
4. Check pause/resume, driver/passenger behavior, a motorcycle, vehicle switching, and a resource restart while already driving.
5. Confirm your fuel resource's level matches the meter and inspect `resmon 1` in each operating state.

## Layout

```text
zz-speedomter/
  fxmanifest.lua
  config.lua
  client.lua
  web/
    index.html
    style.css
    app.js
```

The resource has no server events, persistence, or gameplay authority. It reads local vehicle telemetry and optionally blocks the local exit control.
