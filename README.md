# zz-speedomter

A standalone, Forza-inspired FiveM vehicle HUD. No ESX, QBCore, database, npm build, CDN, custom fonts, or server-side scripts required. All UI assets ship with the resource.

![Compact zz-speedomter HUD, rendered with mocked FiveM messages](docs/preview.png)

Version 1.3.0 removes the fuel display and bottom RPM text. The engine icon is green when healthy and running, red when engine health is below 1000, and dim when healthy but switched off. A dedicated fast RPM sampler and critically damped animation prioritize fluid arc motion. The grey-canvas fix and FiveM-only NUI remain.

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
- Green/red engine status, headlights and high-beam indicators. No fuel meter or bottom RPM caption.
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
| `MaxRpm` | `9000` | Estimated RPM tick scale; falls back to 9000 when omitted |
| `ShowPassenger` | `false` | Also display for passengers |
| `HideWhenPaused` | `true` | Hide when the pause menu is open |
| `UpdateInterval` | `100` | Speed, gear and vehicle checks in milliseconds; minimum 50 |
| `RpmInterval` | `16` | Dedicated RPM sampling in milliseconds; minimum 16; about 60 Hz |
| `IdleInterval` | `750` | Vehicle detection interval on foot |
| `StatusInterval` | `500` | Engine health and light polling interval |
| `Classes` | Road classes | Eligible GTA vehicle classes |
| `Seatbelt.enabled` | `true` | Register belt control and show belt status |
| `Seatbelt.key` | `'B'` | Default key binding |
| `Seatbelt.blockExit` | `true` | Block normal exit while belted |

`/speedunit` toggles units; `/speedunit mph` and `/speedunit kmh` select explicitly. This choice lasts for the client session. **B** or `/zzbelt` toggles the belt. Players can remap the key under **Settings → Key Bindings → FiveM → zz-speedomter: toggle seatbelt**. Existing user mappings take precedence over a changed default.

The seatbelt feature blocks normal vehicle exit only. It does **not** change crash physics, implement ejection, provide damage protection, or make passengers invulnerable. Belt state resets on vehicle change, exit, or death. If another resource manages seatbelts, set `Config.Seatbelt.enabled = false` to avoid conflicting controls.

GTA supplies normalized RPM. The tick numbers estimate engine RPM in thousands using `MaxRpm`; they do not tune the engine. Neutral is shown when the engine is off or the native gear is zero; reverse is detected from backward motion. This is not a transmission simulation. Boats, aircraft, bicycles, and trains are excluded by default.

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

Speed, gear, engine-running state and vehicle eligibility update every 100 ms by default. Engine health and lights update every 500 ms. A separate RPM worker samples every 16 ms while the HUD is visible, retaining 0.01-percent RPM detail and sending only changes. It stops on foot, while paused or suppressed, and when its vehicle disappears. There is no fuel polling or fuel-provider integration. Old fuel config fields are ignored.

The browser updates the arc through one on-demand `requestAnimationFrame` callback. Critically damped motion preserves both drawn position and velocity when readings change, so retargeting does not restart movement. It is time-based, bounded to the dial range, and stops once settled or hidden. Reduced-motion mode snaps directly to readings. Tick marks are built once and only rebuilt when `MaxRpm` changes.

This version deliberately spends more CPU on RPM sampling to prioritize smoothness. Actual sampling depends on game frame scheduling. Increase `Config.RpmInterval` to 33 or 50 for fewer RPM reads; browser interpolation remains active. Other telemetry keeps its independent slower polling rate. No fixed `resmon` number or FPS is promised.

The seatbelt frame worker uses two native calls per frame, down from five. Vehicle class is cached, and stationary vehicles skip reverse-vector reads. For a belt indicator without per-frame exit blocking, use `Config.Seatbelt.blockExit = false`; players can then exit while belted. See `PERFORMANCE.md` for native-call checks and how to capture sustained headlight-related CPU increases with FiveM's profiler.

The NUI startup handshake has a two-second request timeout and up to four retries, with increasing delays. Those timers stop after success; they are separate from vehicle updates.

No `0.00 ms` or fixed FPS claim is made. Actual CPU usage depends on your server, hardware, frame rate, and other resources. Use `resmon 1` in FiveM to check this resource on foot, driving, and belted. Lower `UpdateInterval` values increase native calls and NUI traffic.

### FiveM-only NUI

The NUI activates only when FiveM provides `GetParentResourceName`. Opening the HTML in a normal browser, including with `?preview`, stays blank. There are no full-screen presentation backgrounds, forms, or demo controls. Tests mock the FiveM interface externally; that harness is not part of the runtime resource.

The default footprint is approximately 280 × 302 pixels, smaller than the original 320 × 374. Only local dial shading and the status row paint a background. The page uses a normal color scheme and transparent root/body so embedded Chromium does not substitute an opaque dark canvas.

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
3. Toggle headlights/high beams, toggle the belt and try exiting. Unbelt and exit; verify the HUD hides.
4. Check pause/resume, driver/passenger behavior, a motorcycle, vehicle switching, and a resource restart while already driving.
5. Damage and repair the engine; verify the icon changes green/red correctly. Inspect `resmon 1` in each operating state.

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
