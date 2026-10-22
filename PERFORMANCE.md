# zz-speedomter review

## Verified locally

- **58 checks in Lua 5.4**, running the real client script with mocked FiveM natives and a deterministic scheduler.
- **21 browser tests in Chromium**, using the real HTML/CSS/JavaScript and NUI message protocol.
- JavaScript syntax validation.
- Embedded-frame pixel regression for the grey canvas, plus visual inspection against dark and synthetic bright backgrounds. These are browser renders, not GTA screenshots.

## Work budget at default settings

| State | Behavior verified by the tests |
| --- | --- |
| On foot | Vehicle detection every 750 ms; no speed/RPM/fuel sampling; no seatbelt worker |
| Driving | Speed/RPM sampled at 10 Hz; slower status reads at 2 Hz |
| 10-second unchanged state | 100 speed reads, 20 fuel reads, **zero additional telemetry messages** |
| Speed-only change | Only the changed speed field is sent to NUI |
| Paused or suppressed | HUD telemetry/status sampling stops |
| Unbelted | No per-frame seatbelt worker |
| Belted, exit blocking enabled | Per-frame exit-control suppression, required by FiveM |
| Belt frame-worker native budget | Two calls per frame, reduced from five: current-vehicle check and player exit-control suppression |
| Vehicle class | Queried once per observed vehicle rather than every active tick |
| Parked, engine off | No reverse-vector or gear reads |
| Stable lights off / low beam / high beam | Same 2-Hz light polling, no repeated NUI messages or extra worker |
| Light-only browser updates | No RPM frame scheduled; repeated light state does not mutate the DOM |
| Browser idle | No telemetry polling timer; RPM animation stops after settling |
| Moving RPM | One frame callback updates only the arc, between 10 Hz game readings |
| Hidden HUD or background document | Pending RPM frame callback is cancelled |
| 30 / 60 / 144 Hz simulated frames | Matching arc progress at equal elapsed time |
| RPM retargets during movement | Position stays continuous, with one pending frame callback |
| Repeated configuration | Static arcs retained; tick marks rebuilt only when `MaxRpm` changes |
| Embedded, hidden HUD | Every background pixel matches the host scene before and after hiding |
| Embedded, visible HUD | Sampled pixels outside the HUD remain identical to the host scene |
| 1,000 identical browser updates | No extra DOM mutations from duplicate message handling, separate from active animation frames |
| 100-second changing-telemetry simulation | One telemetry packet per active tick; no additional worker threads |
| 200 rapid belt toggle pairs | One on-demand worker, which exits without applying an exit block |
| Disabled seatbelt / indicator-only mode | No belt command when disabled; no frame worker without exit blocking |
| NUI startup request stalls | Aborted after 2 seconds and retried with bounded backoff; timeout is cleared after completion |

These are simulated scheduling/message counts, **not measured in-game CPU times**. Real frames can delay scheduling, and actual engine RPM or fuel fluctuation naturally generates additional updates.

The telemetry and status buffers are reused. Message objects are allocated only when data changes. State resets occur on vehicle eligibility transitions rather than on every idle tick. There are no server scripts, network events, runtime package dependencies, external fonts, remote UI assets, blur filters, continuous flashing effects, or fixed `will-change` compositor hints.

Text, attributes, hidden state, and configuration styles are written only when their displayed values change. Startup timers exist only during the bounded NUI handshake; they do not poll telemetry. Additional regression checks cover passenger/pause options, custom fuel capacity, initial MPH units, interval limits, and game-timer wraparound.

RPM readings now retain 0.1-percent detail instead of 1-percent steps, without increasing native polling frequency. An on-demand frame callback uses exponential damping with a 60 ms time constant. It advances from the displayed value toward the latest target, never overshoots, and snaps the imperceptible tail to its target before stopping. Reduced motion bypasses animation. Frame-driven animation necessarily adds SVG painting work while RPM changes; no universal frame-time or FPS improvement is claimed.

The seatbelt worker reuses the ped validated when buckling and checks the current vehicle each frame. Death and driver eligibility remain checked by the normal active poll. The duplicate control-group 27 call was removed; player control group 0 handles exit suppression. This reduces that worker's native-call count by 60%, **not a measured 60% reduction in total CPU time**. See the [official native reference](https://github.com/citizenfx/natives/blob/master/PAD/DisableControlAction.md) for the per-frame requirement and input groups.

## Visual checks

- FiveM-only transparent overlay: removed browser demo markup, styles, and activation logic.
- Removed the forced dark color scheme, which reproduced an opaque `(18,18,18)` canvas in an embedded frame despite transparent root/body CSS. After the fix, the test's `(33,66,99)` host background remains unchanged.
- Restored the earlier detailed dial, estimated RPM readout, gear badge, ZZ wordmark, fuel labels, and status row.
- Reduced default footprint of approximately 280 × 327 pixels, 12.5% smaller in each dimension than the original 320 × 374.
- Feathered shading and status/fuel backing improve readability without any full-screen layer.
- Layout tested at 720p, 1080p, ultrawide 1080p, and 4K.
- Scale range 0.65–1.5 tested at 720p with a 10% safe-zone inset. Speed, gear, status icons, and fuel remain separate.
- Redline color checked after its transition settles; seatbelt/fuel visibility and reduced-motion support included.
- Safe-zone placement refreshes after leaving the pause menu.

## Still requires an actual FiveM session

There is no defensible universal “fully optimized” or `0.00 ms` guarantee. This environment cannot run a GTA/FiveM client, so native integration, real frame time, other HUD conflicts, fuel-provider compatibility, and daylight/night readability inside GTA remain unmeasured.

On a representative server/client, use `resmon 1` to compare on-foot, driving, and belted states. Check F8 for errors; test entry, reverse, units, lights, fuel, pause/resume, bike exclusion, belt exit blocking, and a resource restart while already driving. If the server has another speedometer or belt system, disable the overlapping component or this resource's optional belt handler.

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
