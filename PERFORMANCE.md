# zz-speedomter 1.3.0 review

## Verified locally

- **63 Lua checks**, running the real client script in Lua 5.4 with deterministic scheduling and mocked FiveM natives.
- **22 Chromium tests**, running the actual NUI and its message protocol.
- JavaScript syntax and Git whitespace checks.
- Embedded-browser pixel regression: no opaque grey layer before, during, or after HUD visibility.
- Visual inspection and recorded RPM motion use browser renders with mocked data, not GTA screenshots.

## Work budget

| State | Verified behavior |
| --- | --- |
| On foot | One vehicle-detection loop, 750-ms sleeps, no RPM or fuel reads |
| Visible vehicle | Independent 100-ms speed/gear/eligibility and 16-ms RPM workers |
| Health and lights | 500-ms polling; engine running state checked by the 100-ms loop |
| 10-second unchanged simulation | 100 speed reads, 625 RPM reads, 20 light reads, zero fuel reads and no repeated telemetry messages |
| Moving RPM | 0.01-percent detail, sent as RPM-only packets; other fields keep their slower cadence |
| Hidden/paused/suppressed | Fast RPM sampler exits; browser animation cancels |
| Temporary invalid vehicle | RPM worker stops safely and restarts after validation |
| Rapid hide/show | At most one active RPM worker |
| Fuel and legacy fuel providers | No native calls, provider calls or telemetry fields |
| Belt exit blocking | Two native calls per frame; no belt worker when unbelted or exit blocking disabled |
| Vehicle class | Cached per observed vehicle |
| Parked, engine off | No RPM, reverse-vector or gear reads |
| Stable lights off / low / high | Equal light polling; no repeated light packets or additional animation |
| Browser RPM motion | One frame callback, preserving position and velocity across targets |
| 30 / 60 / 144 Hz simulated frames | Matching progress at equal elapsed time |
| Settled / hidden / backgrounded | No continuing RPM animation callbacks |
| Repeated messages/config | No extra DOM writes from duplicate handling; ticks rebuilt only if dial scale changes |

These are native-call/message counts from simulations, not measured in-game CPU times. The main and RPM workers reuse state and send changes only. The dedicated RPM sampler adds native calls and potentially more local NUI messages than version 1.2.0. This is an intentional smoothness tradeoff, not a claim of lower total CPU time. Game frame scheduling determines the actual cadence. `Config.RpmInterval = 33` or `50` reduces RPM sampling while retaining interpolation.

The browser uses exact critically damped motion with a 20-ms spring time scale. Position and velocity continue across new targets. The displayed range is clamped to 0–100 percent; abrupt target changes can retain a small amount of motion before reversing. Once both error and velocity are negligible, the arc snaps to its target and the callback stops. Reduced motion bypasses the animation. Other UI elements are not redrawn by the frame callback.

The seatbelt worker still uses one current-vehicle check and one player exit-control suppression per frame. Main polling handles death and driver eligibility. See the [official native reference](https://github.com/citizenfx/natives/blob/master/PAD/DisableControlAction.md) for the per-frame control requirement. Its native-call budget is reduced from the original five to two; this is not a measured 60% reduction in total resource CPU time.

## Visual checks

- Detailed dial, speed, gear, status icons and ZZ wordmark retained.
- Fuel meter, fuel icon, bottom RPM readout and RPM explanation removed from the HTML and CSS.
- Engine indicator: green when healthy/running; red whenever reported engine health is below 1000; dim when healthy/off. Repair clears red. These semantic colors remain green/red even with a custom dial accent.
- Approximately 280 × 302 pixels at the default scale; layouts checked from 720p to 4K and scales 0.65–1.5.
- Normal color scheme, transparent root/body, no browser demo and no full-screen background.
- Safe-zone placement refreshes after leaving the pause menu.

## Requires a FiveM client

GTA/FiveM is not available in this cloud machine. Real native costs, frame time, other HUD interactions and in-game day/night readability remain unmeasured. Test acceleration, shift RPM drops, braking, reverse, engine start/stop, damage/repair, lights, pause/resume, seatbelt exit blocking, vehicle changes and resource restart. Use `resmon 1` to measure the deliberate high-rate RPM cost on your client; no universal 0.00-ms or fixed FPS guarantee is made.

### Sustained headlight CPU increase

A sustained increase with headlights on was reported in-game. The local regression cases show equal light polling and no message/animation storm in all three steady light states, but this does **not** establish that the reported in-game issue is fixed. Native execution cost, changing real telemetry, and interactions with other resources cannot be reproduced by mocked natives.

After updating, compare the same stationary vehicle with its engine running, belt off, and lights off/on, waiting 10 seconds between changes. Keep the frame cap and other resources unchanged. If `zz-speedomter` still stays substantially higher with lights on, capture each condition in the client F8 console:

```text
profiler record 500
```

When the recording finishes, inspect it with `profiler view` or save separate captures:

```text
profiler saveJSON zz-speedomter-lights-off.json
```

Repeat with lights on and save `zz-speedomter-lights-on.json`. The captures are needed to identify the actual expensive Lua/native call instead of guessing from a resource average. To isolate belt overhead, repeat the same comparison with only belt state changed. `Config.Seatbelt.blockExit = false` removes the belt frame worker entirely while retaining the belt indicator and toggle, but allows normal vehicle exit while belted.
