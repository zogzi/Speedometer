# zz-speedomter review

## Verified locally

- **48 checks in Lua 5.4**, running the real client script with mocked FiveM natives and a deterministic scheduler.
- **12 browser tests in Chromium**, using the real HTML/CSS/JavaScript and NUI message protocol.
- JavaScript syntax validation.
- Visual inspection against dark preview and synthetic bright backgrounds. These are browser renders, not GTA screenshots.

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
| Browser idle | No telemetry polling timer or animation loop |
| Repeated configuration | Static SVG dial retained when its RPM scale stays the same |
| 1,000 identical browser updates | Zero DOM mutations; repeating visibility/configuration also leaves the DOM unchanged |
| 100-second changing-telemetry simulation | One telemetry packet per active tick; no additional worker threads |
| 200 rapid belt toggle pairs | One on-demand worker, which exits without applying an exit block |
| Disabled seatbelt / indicator-only mode | No belt command when disabled; no frame worker without exit blocking |
| NUI startup request stalls | Aborted after 2 seconds and retried with bounded backoff; timeout is cleared after completion |

These are simulated scheduling/message counts, **not measured in-game CPU times**. Real frames can delay scheduling, and actual engine RPM or fuel fluctuation naturally generates additional updates.

The telemetry and status buffers are reused. Message objects are allocated only when data changes. State resets occur on vehicle eligibility transitions rather than on every idle tick. There are no server scripts, network events, runtime package dependencies, external fonts, remote UI assets, blur filters, continuous flashing effects, or fixed `will-change` compositor hints.

Text, attributes, hidden state, and configuration styles are written only when their displayed values change. Startup timers exist only during the bounded NUI handshake; they do not poll telemetry. Additional regression checks cover passenger/pause options, custom fuel capacity, initial MPH units, interval limits, and game-timer wraparound.

## Visual checks

- Transparent overlay with a feathered dark dial, legible tabular speed digits, restrained mint accent, and distinct amber/red/blue warning states.
- Subtle dark backing for status icons and fuel to improve readability against bright scenes.
- Layout tested at 720p, 1080p, ultrawide 1080p, and 4K.
- Scale range 0.65–1.5 tested at 720p with a 10% safe-zone inset. Speed and gear areas remain separate, and branding does not overlap status icons.
- Redline color checked after its transition settles; seatbelt/fuel visibility and reduced-motion support included.
- Safe-zone placement refreshes after leaving the pause menu.

## Still requires an actual FiveM session

There is no defensible universal “fully optimized” or `0.00 ms` guarantee. This environment cannot run a GTA/FiveM client, so native integration, real frame time, other HUD conflicts, fuel-provider compatibility, and daylight/night readability inside GTA remain unmeasured.

On a representative server/client, use `resmon 1` to compare on-foot, driving, and belted states. Check F8 for errors; test entry, reverse, units, lights, fuel, pause/resume, bike exclusion, belt exit blocking, and a resource restart while already driving. If the server has another speedometer or belt system, disable the overlapping component or this resource's optional belt handler.
