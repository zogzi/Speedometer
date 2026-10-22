# zz-speedomter

A standalone, Forza-inspired FiveM vehicle HUD. No ESX, QBCore, database, npm build, CDN, custom fonts, or server-side scripts required. All UI assets ship with the resource.

![Compact zz-speedomter HUD, rendered with mocked FiveM messages](docs/preview.png)

Version 1.2.0 brings back the earlier detailed dial, status row, and RPM readout at a reduced size. The RPM arc now interpolates smoothly between finer readings. The grey-canvas fix remains, and the NUI contains no demo page or browser preview mode.

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
- Optional seatbelt toggle with exit blocking. The status row shows engine, belt, and light states; bikes have no belt indicator.
- Driver-only display by default; hides on foot, on death, in unsupported vehicle classes, and in the pause menu.
- Safe-zone-aware placement, configurable size and accent color, transparent NUI, and no input focus capture.

Edit `config.lua` and restart the resource to apply configuration changes:

| Option | Default | Purpose |
| --- | --- | --- |
| `Unit` | `'kmh'` | Initial speed units |
| `Scale` | `1.0` | HUD size, clamped to 0.65–1.5 |
| `Position` | right 32, bottom 28 | Pixel offset, plus GTA safe-zone inset |
| `Accent` | `'#62f5bb'` | Six-digit hex accent color |
| `MaxRpm` | `9000` | Estimated RPM dial/readout scale; falls back to 9000 when omitted |
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

GTA supplies normalized RPM. The dial and numeric readout estimate engine RPM using `MaxRpm`; they do not tune the engine. Neutral is shown when the engine is off or the native gear is zero; reverse is detected from backward motion. This is not a transmission simulation. Boats, aircraft, bicycles, and trains are excluded by default.

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

The client polls telemetry at 10 Hz by default, rounds speed and retains RPM to 0.1-percent precision, and sends only changed fields to NUI. Telemetry and status buffers are reused; message objects are created only when data changes. Fuel, engine health, and lights are read at 2 Hz. On foot, the main loop sleeps for 750 ms. Repeated display values do not rewrite DOM text or attributes. Tick marks are built once and only rebuilt when `MaxRpm` changes. A Lua frame loop is necessary **only while belted with exit blocking enabled**, because FiveM control suppression lasts one frame.

The browser uses one `requestAnimationFrame` callback while the RPM arc moves. It applies time-based damping to the latest target, so updates continue from the current drawn position at the browser's refresh rate. There is no stacked CSS length transition. The callback stops after the arc settles, when the HUD hides, or when the document goes into the background. Reduced-motion mode snaps directly to readings. Other UI elements are not repainted by this callback, and the browser does not poll the game or increase Lua sampling frequency.

The seatbelt frame worker uses two native calls per frame, down from five. Vehicle class is cached, and stationary vehicles skip reverse-vector reads. For a belt indicator without per-frame exit blocking, use `Config.Seatbelt.blockExit = false`; players can then exit while belted. See `PERFORMANCE.md` for native-call checks and how to capture sustained headlight-related CPU increases with FiveM's profiler.

The NUI startup handshake has a two-second request timeout and up to four retries, with increasing delays. Those timers stop after success; they are separate from vehicle updates.

No `0.00 ms` or fixed FPS claim is made. Actual CPU usage depends on your server, hardware, frame rate, and other resources. Use `resmon 1` in FiveM to check this resource on foot, driving, and belted. Lower `UpdateInterval` values increase native calls and NUI traffic.

### FiveM-only NUI

The NUI activates only when FiveM provides `GetParentResourceName`. Opening the HTML in a normal browser, including with `?preview`, stays blank. There are no full-screen presentation backgrounds, forms, or demo controls. Tests mock the FiveM interface externally; that harness is not part of the runtime resource.

The default footprint is approximately 280 × 327 pixels, smaller than the original 320 × 374. Only the local dial shading, status row, and fuel meter paint a background. The page uses a normal color scheme and transparent root/body so embedded Chromium does not substitute an opaque dark canvas.

### Automated checks

Runtime deployment needs only the files listed in `fxmanifest.lua`. Run the following development checks from the repository checkout; the deployment ZIP omits the `tests` directory:

```sh
node --check web/app.js
lua5.4 tests/client_spec.lua
# Alternative on Linux with Python and liblua5.4 installed:
python tests/run_lua_tests.py

# Requires Python Playwright, Pillow, and Chromium for development only:
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
