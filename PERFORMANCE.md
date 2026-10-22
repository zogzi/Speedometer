# zz-speedomter 1.7.0 motion and performance review

Version 1.7.0 deliberately prioritizes fluid speed/RPM motion over the lower active CPU budget of 1.6.0. The default is now `Config.UpdateInterval = 0`, meaning one telemetry sample per game frame through `Wait(0)`. The HUD is 15% smaller through `Config.Scale = 0.85`.

## What changed

| Behavior | 1.6.0 | 1.7.0 default |
| --- | --- | --- |
| Active sampling | Every 100 ms | Every game frame |
| Speed sent to NUI | Rounded integer | Full fractional reading |
| RPM sent to NUI | Half-percent increments | Full fractional reading |
| Speed display | Jumps to each received number | Animates between readings, then rounds for display |
| RPM arc | Time-based spring | Same continuous spring, finer inputs and stroke precision |
| Browser animation | One RPM callback | One shared speed/RPM callback |
| Default footprint | 360 × 320 pixels | 306 × 272 pixels |
| Side icon size | 26 pixels | About 22 pixels |

Both gauges preserve position and velocity across incoming readings. The exact critically damped spring advances to each packet's receipt time before switching targets, avoiding repeated easing restarts. Its time scale is about 56 ms, adding roughly 110 ms of display delay during a steady ramp. Higher sampling reduces the separate delay before a new vehicle reading arrives. Abrupt changes can retain a little motion before reversing, but values stay bounded to 0–999 speed and 0–100% RPM. Gear changes remain immediate; fractional speed is rounded only when painted. Switching units converts the current speed and velocity instead of animating a false speed change.

## Current work budget

A visible, moving vehicle performs one velocity-vector read, one RPM read (engine running), one gear read (engine running), and shared eligibility checks per game frame. At 60 game frames per second this is roughly 60 of each active read per second, compared with roughly 10 in 1.6.0. This is a sampling comparison, not a CPU percentage or frame-rate guarantee. Only changed fields are sent, together in at most one telemetry packet per sample. Fractional precision means small fluctuations can now generate packets that older releases suppressed.

The vector still supplies both full 3D speed and reverse direction, avoiding a redundant scalar native while moving. The [vector3 documentation](https://github.com/citizenfx/fivem-docs/blob/master/content/docs/scripting-reference/runtimes/lua/functions/vector3.md) defines vector length, and [GetEntitySpeedVector](https://github.com/citizenfx/natives/blob/master/ENTITY/GetEntitySpeedVector.md) documents local direction. Parked vehicles use a scalar-only motion probe. Vehicle class is cached; engine-off vehicles skip RPM/gear natives. Health/lights are checked about every 500 ms, subject to frame scheduling. Hidden/paused HUDs skip telemetry and check eligibility every 100 ms by default; on-foot detection sleeps 750 ms. No fuel provider or separate RPM worker exists.

The optional belt worker calls only `DisableControlAction(0, 75, true)` each frame while belted. The main loop validates vehicle/seat/death state. After validation clears the belt, the worker ends on its next frame. No belt worker runs while unbelted or with `Seatbelt.blockExit = false`.

Browser rendering shares one on-demand frame callback. Hidden, backgrounded and settled gauges stop scheduling callbacks. Reduced-motion preferences snap to readings. Static ticks are retained; unchanged text/attributes are not rewritten. The SVG arc still requires painting; this is not a compositor-only animation. Changing speed text also incurs browser layout work.

Set `Config.UpdateInterval = 100` to restore the older sampling cadence while retaining the new speed and RPM animation. The new frame-based mode is the shipping default because fluidity is the requested priority. Older explicit config values remain honored.

## Validation

- **81 Lua checks** execute the real client with Lua 5.4 and mocked FiveM natives. Existing lifecycle/work-budget tests cover the optional 100-ms mode. Additional tests verify shipping defaults, one sample per simulated frame, combined packets, fractional values, pause backoff, and vehicle/belt changes. The scheduler models `Wait(0)` as a 16-ms frame; it is not a GTA benchmark.
- **29 Chromium tests** cover speed counting/braking, fractional frame-rate inputs, shared animation scheduling, unit conversion, 30/60/144-Hz retargeting, settling/visibility/reduced motion, warnings, layouts and transparent embedded canvases. A steady 60-Hz RPM ramp must keep fastest/slowest frame motion within 1.05× after warmup; the optional 100-ms ramp retains its 1.5× limit.
- JavaScript syntax and Git whitespace checks.
- Preview images and the motion recording use mocked telemetry, not GTA footage.

`python tests/profile_ui.py` records local Chromium work counters with 16-ms mock messages. See [docs/ui-profile.json](docs/ui-profile.json). These counters include harness work and do not measure FiveM Lua/native execution, GTA frame times, CEF GPU costs or performance relative to qb-hud.

## Visual and in-game checks

The default dial is 272 pixels across with unboxed icons following its left curve. Neutral silver-white/charcoal colors remain; engine damage is red, healthy/running green, belt warning amber and high beams blue. There is no fuel bar, branding, bottom RPM explanation or SPEED/GEAR caption. Transparent root/body and normal color scheme preserve the grey-screen fix. Layout tests cover 720p–4K and scales 0.65–1.5. Bright/dark previews use synthetic backgrounds.

Actual GTA/FiveM is unavailable in this environment. Install the complete update and compare acceleration, gear shifts, braking to zero, reverse, unit changes, pause/resume, vehicle switching, engine damage/repair, belt and lights in game. The higher active resource cost is intentional; no fixed millisecond or FPS claim is made.

For a real resource capture, use the client F8 console:

```text
resmon 1
profiler record 500
profiler view
profiler saveJSON zz-speedomter-driving.json
```

Use NUI developer tools to inspect browser rendering separately. Keep the same vehicle, frame cap and belt/light state when comparing versions or settings. If a sustained light-related cost increase returns, capture separate lights-off/on profiles with the same stationary vehicle. Mocked native calls cannot establish actual in-game native costs.

See [REVIEW.md](REVIEW.md) for the documentation and external source comparisons.
