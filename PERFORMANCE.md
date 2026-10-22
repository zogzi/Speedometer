# zz-speedomter 1.6.0 performance review

See [REVIEW.md](REVIEW.md) for the guide/source comparison, visual contrast fix and local Chromium measurements. Version 1.6.0 removes one redundant native call per steady-driving sample and retains the existing telemetry rate and RPM smoothing. The server owner reports that performance is now good.

## Changes prompted by the reported 0.14-ms cost

Version 1.3.0 added an independent 16-ms RPM worker to prioritize smoothness. Version 1.4.0 removes it. One loop now reads RPM, speed and gear every 100 ms and combines changes into one telemetry packet. Browser interpolation still draws intermediate arc positions. Half-percent RPM precision avoids tiny idle fluctuations triggering messages.

The seatbelt frame loop now contains only the required `DisableControlAction` call. Vehicle, seat and death validation use the shared vehicle poll. Forced exits or vehicle changes may retain exit suppression until that poll, up to 100 ms by default. Normal unbuckling stops the loop immediately on its next iteration.

## Additional 1.6.0 savings

While moving, `GetEntitySpeedVector(vehicle, true)` is already needed for reverse detection. Its vector magnitude also gives the full 3D speed, so the separate `GetEntitySpeed` read is redundant. The [FiveM vector documentation](https://github.com/citizenfx/fivem-docs/blob/master/content/docs/scripting-reference/runtimes/lua/functions/vector3.md) defines `#vector` as its length, and the [native documentation](https://github.com/citizenfx/natives/blob/master/ENTITY/GetEntitySpeedVector.md) defines the relative direction.

| Speed/direction work at default settings | 1.5.0 | 1.6.0 |
| --- | --- | --- |
| Steady driving | 10 scalar + 10 vector reads per second | 10 vector reads per second |
| Parked after settling | 10 scalar reads per second | 10 scalar reads per second |
| First moving tick from rest | Scalar + vector | Scalar + vector |
| Update interval | 100 ms | 100 ms |

This removes 10 native calls per second while steadily driving, not 50% of total resource CPU time. Tests verify full sideways/vertical speed, reverse, stopping and acceleration without adding a sampling interval. Losing an entity also invalidates its class cache before a reused handle can be classified.

## Verified locally

- **72 Lua checks** execute the client script with real Lua 5.4 and mocked FiveM natives.
- **24 Chromium tests** exercise the actual UI, including smooth interpolation, side-icon placement, absence of boxes/captions, engine damage colors and embedded canvas transparency.
- JavaScript syntax and Git whitespace checks.
- Preview images use mocked telemetry, not GTA screenshots.

| Work | Version 1.3.0 | Version 1.6.0 |
| --- | --- | --- |
| Default RPM reads over 10 simulated seconds | 625 | 100 (84% fewer) |
| Separate RPM entity checks | One per RPM iteration | None |
| Telemetry messages when RPM and speed keep changing | Separate RPM and main packets | At most one per 100-ms tick |
| Active telemetry workers | Two | One |
| Belt worker native calls per frame | Two | One |
| Light/health polling | Every 500 ms | Every 500 ms |
| Fuel work | None | None |

After entry, the 10-second unchanged driving test observes 100 velocity-vector reads, zero separate scalar speed reads, 100 RPM reads, 20 light reads and zero repeated telemetry packets. Changing speed and RPM together produces exactly 100 packets over 10 simulated seconds. Lights off, low beams and high beams have the same polling/message behavior in the fixture. These are native-call and message counts, not measured in-game milliseconds.

On foot, vehicle detection sleeps 750 ms. Hidden/paused/suppressed HUDs skip telemetry reads. Parked vehicles skip reverse-vector reads; engine-off vehicles skip RPM and gear reads. Vehicle class is cached. No belt worker runs while unbelted or when `Seatbelt.blockExit = false`. Old `RpmInterval = 16` configs cannot re-enable the removed worker.

Browser motion uses one on-demand frame callback and exact critically damped interpolation, now tuned with a 56-ms time scale for the 100-ms input cadence. Motion advances to the packet timestamp before the target changes, avoiding refresh-rate-dependent progress when messages arrive between frames. The spring adds roughly 110 ms of lag during a steady input ramp, in addition to sampling delay. It preserves position and velocity across samples, behaves consistently at 30/60/144 Hz, and stops when settled, hidden or backgrounded. Reduced-motion mode snaps to readings. The dial range remains bounded to 0–100 percent; abrupt target changes can retain a little motion before reversing. Tick marks and unchanged labels are not rewritten every frame.

## Visual checks

The default dial, RPM arc and gear use silver-white, charcoal and grey. Side icon centers share a 174-pixel radius with even 20-degree spacing. Dial shading stays inside the outer track and text uses a compact shadow instead of the previous broad blur. Unboxed engine, belt and light icons follow the left side of the dial; semantic green/red/amber/blue statuses remain. SPEED/GEAR captions, ZZ branding, status panel, gear box, fuel and bottom RPM explanation are absent. The engine icon is green when healthy/running, red below full engine health (1000), and dim when healthy/off. Default footprint is about 360 × 320 pixels. The dial is 320 pixels across (previously 280), and icons are 26 pixels (previously 17.5). Placement is checked from 720p to 4K and scales 0.65–1.5.

The transparent root/body and normal color scheme remain. Pixel checks verify that the NUI does not paint a grey screen over the game. No browser demo is shipped.

## In-game measurement still required

The reported 0.14-ms resource time and comparison with qb-hud cannot be reproduced on this cloud machine, which has no GTA/FiveM client. No claim of matching 0.04–0.05 ms is made from mocked tests. Update the client and complete web folder, restart the resource, then compare `resmon 1` with the same car, frame cap and other resources on foot, parked, accelerating, belted and with headlights on. Use `Config.UpdateInterval = 100`; old custom values of 50 double the default telemetry frequency.

Verify shifts, reverse, engine start/stop, damage/repair, pause/resume, seat changes, forced vehicle switches and resource restart. To isolate belt cost, compare `Config.Seatbelt.blockExit = false` with the default. The frame-scoped exit native is documented in the [FiveM native reference](https://github.com/citizenfx/natives/blob/master/PAD/DisableControlAction.md).

### Historical headlight CPU report

A sustained increase with headlights on was reported in-game on earlier versions; the user now reports good performance. The following procedure is retained in case the symptom returns. The local regression cases show equal light polling and no message/animation storm in all three steady light states, but this does **not** establish that the reported in-game issue is fixed. Native execution cost, changing real telemetry, and interactions with other resources cannot be reproduced by mocked natives.

After updating, compare the same stationary vehicle with its engine running, belt off, and lights off/on, waiting 10 seconds between changes. Keep the frame cap and other resources unchanged. If `zz-speedomter` still stays substantially higher with lights on, capture each condition in the client F8 console:

```text
profiler record 500
```

When the recording finishes, inspect it with `profiler view` or save separate captures:

```text
profiler saveJSON zz-speedomter-lights-off.json
```

Repeat with lights on and save `zz-speedomter-lights-on.json`. The captures are needed to identify the actual expensive Lua/native call instead of guessing from a resource average. To isolate belt overhead, repeat the same comparison with only belt state changed. `Config.Seatbelt.blockExit = false` removes the belt frame worker entirely while retaining the belt indicator and toggle, but allows normal vehicle exit while belted.
