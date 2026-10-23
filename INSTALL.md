# Install zz-speedomter

This is a standalone FiveM resource. It works without ESX or QBCore. You do not need to install Node, run a build, import SQL, or edit your framework.

## 1. Upload the folder

Extract the download. Copy the **whole `zz-speedomter` folder** into your server's active `resources` directory, for example:

If you downloaded from GitHub using **Code → Download ZIP**, first rename the extracted `Speedometer-main` folder to `zz-speedomter`.

```text
server-data/
  server.cfg
  resources/
    [local]/
      zz-speedomter/
        fxmanifest.lua
        config.lua
        client.lua
        web/
          index.html
          style.css
          app.js
```

For a hosted or txAdmin server, use the file manager or SFTP to access the resources folder used by your active server profile. `[local]` is just an optional category folder. The important part is that `fxmanifest.lua` is directly inside `zz-speedomter`, without an extra `zz-speedomter/zz-speedomter/` nesting level.

## 2. Enable the resource

Add the following line to the **server's `server.cfg`**:

```cfg
ensure zz-speedomter
```

Use exactly this folder name and spelling. Save the file. Then restart the server, or run the following in the **server/txAdmin console** to start it immediately:

```text
refresh
ensure zz-speedomter
```

Adding the `server.cfg` line makes it start automatically after later server restarts. Running only the console command does not save that startup setting.

## 3. Check it in game

Connect to the server and enter the **driver's seat of a car**. The HUD appears within roughly a second. It intentionally hides on foot, as a passenger by default, and in the pause menu.

- **B** or `/zzbelt`: toggle the optional seatbelt. Unfasten it before trying to leave the car.
- `/speedunit`: switch KM/H and MPH.
- **Settings → Key Bindings → FiveM → zz-speedomter: toggle seatbelt**: remap the belt key.

## 4. Match your server

Edit `config.lua`, then run `restart zz-speedomter` from the server console:

```lua
Config.Unit = 'mph' -- or 'kmh'
Config.Scale = 0.85
Config.Position = { right = 32, bottom = 28 }
Config.Accent = '#e7edf0'
Config.UpdateInterval = 0 -- every game frame for the smoothest readings
```

If you already use a speedometer, disable its speedometer component in that resource's settings to prevent overlapping displays. If another resource handles seatbelts, set `Config.Seatbelt.enabled = false` here so both scripts do not compete for the exit control.

## Updating from an older version

Replace `fxmanifest.lua`, `client.lua`, and the **whole `web` folder** together. Use the new `config.lua`, or merge these settings into your custom configuration:

```lua
Config.Scale = 0.85
Config.UpdateInterval = 0
Config.Accent = '#e7edf0'
```

Then run `restart zz-speedomter`. Keeping an old `Scale = 1.0` or `UpdateInterval = 100` preserves the old size or sampling interval; these explicit custom values are not overwritten automatically.

Version 1.7.0 reduces the default footprint from 360 × 320 to 306 × 272 pixels. The dial is 272 pixels across, and icons are about 22 pixels. Both the speed digits and RPM arc interpolate continuously. Speed and RPM now retain fractional readings and sample every game frame, prioritizing smoothness over the previous CPU budget. Whole-number speed is rounded only when drawn. Unit changes convert immediately without a false acceleration/braking transition; gear changes remain immediate.

Version 1.8.0 places the indicators in a row beneath the dial and removes the old side gutter. The complete footprint is now approximately 272 × 299 pixels at Scale 0.85. The engine icon appears only for damage, the belt icon only while unfastened and available, and the light icon only with headlights/high beams on. The remaining icons center together, with no empty gaps. The dial keeps its position when the row is empty. From 1.7.0, replace `fxmanifest.lua` and the complete `web` folder, then restart; Lua behavior, smoothing and config values are unchanged.

You can still select `Config.UpdateInterval = 100` for the earlier lower-cost sampling cadence, with the new smoothing retained. No independent RPM worker is used. Legacy fuel and `RpmInterval` settings remain ignored. Optional `MaxRpm` defaults to 9000, and older custom accent colors remain valid.

The transparent page and grey-screen fix remain. Do not mix old CSS or HTML with the updated files. If the previous display persists after restarting, reconnect and confirm that only the updated copy of the resource is running.

Seatbelt exit blocking uses one native per frame. Vehicle changes, exits and death clear belt state at the next vehicle poll; the belt worker then ends at its next frame. Set `Config.Seatbelt.blockExit = false` for an indicator without exit blocking.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Resource cannot be found | Folder name is `zz-speedomter`; run `refresh`; check for double nesting. |
| No HUD | Resource is started; enter the driver's seat of a road vehicle, close the pause menu, and check the client F8 console for errors. |
| Two speedometers | Disable the old speedometer component in its own settings. |
| Cannot exit the vehicle | Press B to unbuckle; inspect other seatbelt resources if the problem remains. |
| Belt key does nothing | Check the player's saved FiveM key mapping; it overrides the configured default. |
| Grey screen over the game | Replace the complete `web` folder with version 1.1.0 or newer; restart the resource and reconnect if necessary. |

For performance verification, open the client **F8 console** and run `resmon 1`. Compare `zz-speedomter` while on foot, driving, and belted. Run `resmon 0` when finished. This version prioritizes fluidity and performs more active work than 1.6.0. Actual CPU time and visual integration must be checked on your server and hardware.
