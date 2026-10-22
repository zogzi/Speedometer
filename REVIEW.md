# Source and visual review

Reviewed 2026-10-22 against the sources below. Runtime version: 1.4.1.

The resource follows the relevant FiveM and browser guidance and has a small work budget. That does not establish a universal “fully optimized” state or prove a lower in-game cost than another HUD. Real FiveM profiling is still required to locate any remaining expensive native calls or CEF rendering work.

## Guidance checked

| Source | Guidance | Current implementation |
| --- | --- | --- |
| [FiveM Citizen.Wait](https://github.com/citizenfx/fivem-docs/blob/master/content/docs/scripting-reference/runtimes/lua/functions/Citizen.Wait.md) | Sleep when work is unnecessary, avoid heavy per-frame natives, cache infrequently changing values; waits are frame-bound | One 100-ms telemetry loop, 750-ms on-foot sleeps, cached vehicle class; no separate RPM loop |
| [FiveM DisableControlAction](https://github.com/citizenfx/natives/blob/master/PAD/DisableControlAction.md) | Exit suppression must execute every frame | One call per frame only while belted with exit blocking enabled; validation shares the slower loop |
| [FiveM fullscreen NUI](https://github.com/citizenfx/fivem-docs/blob/master/content/docs/scripting-manual/nui-development/full-screen-nui.md) | Declare assets, send JSON messages, use CEF developer tools for UI inspection | Local assets, one changed-field telemetry packet per tick, no focus capture; transparent iframe tested |
| [MDN requestAnimationFrame](https://github.com/mdn/content/blob/main/files/en-us/web/api/window/requestanimationframe/index.md) | Use timestamps for refresh-rate-independent motion; schedule callbacks only as needed | Time-based interpolation, one active callback, explicit cancellation while hidden/backgrounded, no continuing callbacks after settling |
| [MDN animation performance](https://github.com/mdn/content/blob/main/files/en-us/web/performance/guides/animation_performance_and_frame_rate/index.md) | Distinguish layout, paint and composition costs; measure actual animated properties | Static dial geometry; RPM changes one SVG stroke attribute. This still requires paint and is not claimed to be compositor-only or GPU-free |

The public documentation pages were unavailable through this environment's network route; their official GitHub source files were read instead. No external implementation code was copied into the resource.

## Comparison with existing HUDs

Compared the actual client source at these revisions, not advertised resmon screenshots:

- [qb-hud client](https://github.com/qbcore-framework/qb-hud/blob/65d102aeb0de7e2ab08319bc619e85d4c4f55334/client.lua), [default config](https://github.com/qbcore-framework/qb-hud/blob/65d102aeb0de7e2ab08319bc619e85d4c4f55334/config.lua).
- [ps-hud client](https://github.com/Project-Sloth/ps-hud/blob/e28fbfd87135c94bcc95b54f3526c65b21208a1a/client.lua). This shares ancestry with qb-hud, so it is not an independent performance benchmark.

| Behavior | zz-speedomter 1.4.1 | Reviewed qb-hud | Reviewed ps-hud |
| --- | --- | --- | --- |
| Vehicle telemetry cadence | 100 ms by default | 500 ms with default `isChangeFPSChecked = true`; 50 ms with it disabled | 500 ms in logged-in HUD loop |
| Unchanged data | No telemetry packet | Vehicle packet skipped | Vehicle packet skipped |
| Changed data | Changed fields only, combined speed/gear/RPM | Full car packet when any vehicle field changes; separate player HUD packet | Full car status packet when any vehicle field changes; separate player HUD packet |
| RPM arc | Included, interpolated in browser | No RPM field in reviewed car packet | No RPM field in reviewed car packet |
| Fuel | Removed | Provider result cached for 2 seconds | Provider result cached for 2 seconds |
| Scope | Vehicle instruments and optional exit blocking | Also player stats, map/compass, voice, stress, etc. | Also player stats, map/compass, voice, stress, etc. |

The default qb-hud and ps-hud loops sample five times less frequently than this resource. That is a responsiveness tradeoff. On the other hand, they serve more features. Neither source size nor feature count predicts a comparable resmon result by itself.

Seatbelt accounting matters too: qb-hud listens to seatbelt events, while [qb-smallresources handles exit blocking and additional seatbelt behavior](https://github.com/qbcore-framework/qb-smallresources/blob/main/client/seatbelt.lua). Our optional exit block runs inside this resource. Comparing only the `qb-hud` resource row excludes that other resource's cost.

Keep `Config.UpdateInterval = 100` for the current response. A value of `200` halves the telemetry polling rate but adds response delay. A value of `500` matches the reviewed default HUD polling rate and makes readings visibly less responsive. Interpolation continues at any setting; it cannot invent changes that have not yet been sampled. These are tuning options, not evidence of a particular CPU time.

## Visual review

Checked the real page against bright and dark backgrounds, compact/default/enlarged scales, 720p through 4K, warning states, and an embedded transparent iframe. Speed and units remain central; gear and curved side icons are unboxed. No ZZ branding, SPEED/GEAR descriptions, fuel bar or bottom RPM caption is present.

One concrete issue was found: thin green icons had weak contrast over bright backgrounds. Version 1.4.1 adds a static dark SVG outline behind each icon. It adds no animation loop, background panel, blur or filter. Engine green/red and high-beam blue remain intact. [Bright preview](docs/preview-bright.png) and [dark preview](docs/preview-dark.png) use synthetic backgrounds, not GTA screenshots. Day/night readability still needs an in-game look.

## Browser measurement

`python tests/profile_ui.py` runs the production NUI in local Chromium, with externally mocked FiveM messages every 100 ms. It measures hidden, settled, RPM-only and changing speed/RPM scenarios for three seconds each after warmup. The [recorded output](docs/ui-profile.json) includes browser version, callback counts, layouts and DevTools timing counters.

In the recorded run, hidden and settled cases each had zero RPM callbacks, zero layouts and zero style recalculations. RPM-only motion produced 175 callbacks over about three seconds with zero layouts. Updating speed as well produced 29 layouts, corresponding to changing speed text rather than every animation frame. SVG stroke animation still recalculates styles and repaints.

This harness isolates DOM/animation work. Timings include the harness and are specific to this cloud machine; they are not FiveM Lua milliseconds, GTA frame times, CEF/GPU totals or a qb-hud benchmark. No performance threshold is asserted. In-game profiling should use the same car, game frame cap, belt state and headlight state, with both the resource profiler and NUI developer tools where appropriate.

The existing 65 Lua checks cover telemetry budgets and lifecycle behavior. All 22 browser regression tests were rerun after the outline change, including engine colors, layouts, smoothness, settled/hidden cancellation and the grey-canvas regression. See [PERFORMANCE.md](PERFORMANCE.md) for exact work counts and the in-game measurement procedure.
