# Source and visual review

Reviewed 2026-10-22 against the sources below. Runtime version: 1.7.0. This release intentionally raises the default sampling rate to every game frame and smooths speed as well as RPM, prioritizing fluidity at the user’s request. The external revisions below are unchanged from the source review.

The resource uses the relevant FiveM and browser techniques; its active work budget is now deliberately higher than 1.6.0. That does not establish a universal “fully optimized” state or prove a lower in-game cost than another HUD. Real FiveM profiling is still required to locate any remaining expensive native calls or CEF rendering work.

## Guidance checked

| Source | Guidance | Current implementation |
| --- | --- | --- |
| [FiveM Citizen.Wait](https://github.com/citizenfx/fivem-docs/blob/master/content/docs/scripting-reference/runtimes/lua/functions/Citizen.Wait.md) | Sleep when work is unnecessary, avoid heavy per-frame natives, cache infrequently changing values; waits are frame-bound | One frame-based telemetry loop while visible, 100-ms hidden checks, 750-ms on-foot sleeps, cached vehicle class; optional 100-ms sampling |
| [FiveM DisableControlAction](https://github.com/citizenfx/natives/blob/master/PAD/DisableControlAction.md) | Exit suppression must execute every frame | One call per frame only while belted with exit blocking enabled; validation shares the main telemetry/eligibility loop |
| [FiveM fullscreen NUI](https://github.com/citizenfx/fivem-docs/blob/master/content/docs/scripting-manual/nui-development/full-screen-nui.md) | Declare assets, send JSON messages, use CEF developer tools for UI inspection | Local assets, one changed-field telemetry packet per tick, no focus capture; transparent iframe tested |
| [MDN requestAnimationFrame](https://github.com/mdn/content/blob/main/files/en-us/web/api/window/requestanimationframe/index.md) | Use timestamps for refresh-rate-independent motion; schedule callbacks only as needed | Time-based interpolation, one active callback, explicit cancellation while hidden/backgrounded, no continuing callbacks after settling |
| [MDN animation performance](https://github.com/mdn/content/blob/main/files/en-us/web/performance/guides/animation_performance_and_frame_rate/index.md) | Distinguish layout, paint and composition costs; measure actual animated properties | Static dial geometry; RPM changes one SVG stroke attribute; animated speed text can cause layout. This still requires paint and is not claimed to be compositor-only or GPU-free |

The public documentation pages were unavailable through this environment's network route; their official GitHub source files were read instead. No external implementation code was copied into the resource.

## Comparison with existing HUDs

Compared the actual client source at these revisions, not advertised resmon screenshots:

- [qb-hud client](https://github.com/qbcore-framework/qb-hud/blob/65d102aeb0de7e2ab08319bc619e85d4c4f55334/client.lua), [default config](https://github.com/qbcore-framework/qb-hud/blob/65d102aeb0de7e2ab08319bc619e85d4c4f55334/config.lua).
- [ps-hud client](https://github.com/Project-Sloth/ps-hud/blob/e28fbfd87135c94bcc95b54f3526c65b21208a1a/client.lua). This shares ancestry with qb-hud, so it is not an independent performance benchmark.

| Behavior | zz-speedomter 1.7.0 | Reviewed qb-hud | Reviewed ps-hud |
| --- | --- | --- | --- |
| Vehicle telemetry cadence | Every game frame by default; 100 ms optional | 500 ms with default `isChangeFPSChecked = true`; 50 ms with it disabled | 500 ms in logged-in HUD loop |
| Unchanged data | No telemetry packet | Vehicle packet skipped | Vehicle packet skipped |
| Changed data | Changed fields only, combined speed/gear/RPM | Full car packet when any vehicle field changes; separate player HUD packet | Full car status packet when any vehicle field changes; separate player HUD packet |
| RPM arc | Included, interpolated in browser | No RPM field in reviewed car packet | No RPM field in reviewed car packet |
| Fuel | Removed | Provider result cached for 2 seconds | Provider result cached for 2 seconds |
| Scope | Vehicle instruments and optional exit blocking | Also player stats, map/compass, voice, stress, etc. | Also player stats, map/compass, voice, stress, etc. |

The reviewed default qb-hud and ps-hud loops sample much less frequently than this resource’s new frame-based mode. That is a responsiveness tradeoff. On the other hand, they serve more features. Neither source size nor feature count predicts a comparable resmon result by itself.

Seatbelt accounting matters too: qb-hud listens to seatbelt events, while [qb-smallresources handles exit blocking and additional seatbelt behavior](https://github.com/qbcore-framework/qb-smallresources/blob/main/client/seatbelt.lua). Our optional exit block runs inside this resource. Comparing only the `qb-hud` resource row excludes that other resource's cost.

Use `Config.UpdateInterval = 0` for the new fluidity-focused default. `100` restores the prior sampling cadence, while `500` matches the reviewed default HUD polling rate and makes readings less responsive. Interpolation continues at any setting; it cannot invent changes that have not yet been sampled. These are tuning options, not evidence of a particular CPU time.

## Additional runtime review in 1.6.0

The earlier client separately read scalar speed and local velocity on each moving tick. Version 1.6.0 reuses the velocity magnitude for speed, removing one native call per moving sample while retaining scalar-only parked checks (10 calls per second at the former default 100-ms interval). The vector reuse does not reduce sample frequency or omit sideways/vertical speed. Tests also verify stopping, restarting, reverse and cache invalidation after entity disappearance. See [PERFORMANCE.md](PERFORMANCE.md) for the measured call budget and native references.

## Visual review

Checked the real page against bright and dark backgrounds, compact/default/enlarged scales, 720p through 4K, warning states, and an embedded transparent iframe. Speed and units remain central; gear and curved side icons are unboxed. No ZZ branding, SPEED/GEAR descriptions, fuel bar or bottom RPM caption is present.

Version 1.5.0 increases the dial from 280 to 320 displayed pixels and icons from 17.5 to 26 pixels at Scale 1.0. That 1.5/1.6 footprint is 360 × 320 pixels. Version 1.7.0 uses Scale 0.85 by default, reducing it to 306 × 272 pixels with approximately 22-pixel side icons. Version 1.6.0 places the icon centers on a common radius with equal angular spacing, contains the shading within the track, and uses a compact text shadow. A neutral silver-white/charcoal palette replaces the green dial accent; engine damage, belt warnings and high beams retain semantic colors.

One concrete issue was found: thin green icons had weak contrast over bright backgrounds. Version 1.4.1 adds a static dark SVG outline behind each icon. It adds no animation loop, background panel, blur or filter. Engine green/red and high-beam blue remain intact. [Bright preview](docs/preview-bright.png) and [dark preview](docs/preview-dark.png) use synthetic backgrounds, not GTA screenshots. Day/night readability still needs an in-game look.

## Browser measurement

`python tests/profile_ui.py` runs the production NUI in local Chromium, with externally mocked FiveM messages every 16 ms. It measures hidden, settled, RPM-only and changing speed/RPM scenarios for three seconds each after warmup. The [recorded output](docs/ui-profile.json) includes browser version, callback counts, layouts and DevTools timing counters.

Hidden and settled cases have no continuing RPM callbacks or layout work. RPM-only animation avoids layout; smoothed speed text can trigger layout as its displayed integer changes. SVG stroke animation still recalculates styles and repaints.

The earlier RPM spring was tuned for 16-ms sampling and nearly reached each target before the next 100-ms reading. Version 1.5 corrected that surge-and-slow pattern. Version 1.7 keeps the continuous spring, feeds it fractional frame-rate readings, and applies the same motion to speed. Tests check smooth speed counting, braking, 30/60/144-Hz timing, unit conversion and a steady 60-Hz RPM ramp with fastest/slowest frame movement within 1.05× after warmup. The optional 100-ms input mode also retains its smoothness test. The spring adds roughly 110 ms of smoothing delay during a steady ramp.

This harness isolates DOM/animation work. Timings include the harness and are specific to this cloud machine; they are not FiveM Lua milliseconds, GTA frame times, CEF/GPU totals or a qb-hud benchmark. No performance threshold is asserted. In-game profiling should use the same car, game frame cap, belt state and headlight state, with both the resource profiler and NUI developer tools where appropriate.

The 81 Lua checks cover telemetry budgets and lifecycle behavior. All 29 browser regression tests pass after the size and smoothing changes, including engine colors, layouts, smoothness, settled/hidden cancellation and the grey-canvas regression. See [PERFORMANCE.md](PERFORMANCE.md) for exact work counts and the in-game measurement procedure.
