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

Add the following line to the **server's `server.cfg`**, ideally after your fuel resource if you use a custom fuel provider:

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
Config.Scale = 1.0
Config.Position = { right = 32, bottom = 28 }
Config.Accent = '#62f5bb'
```

If you already use a speedometer, disable its speedometer component in that resource's settings to prevent overlapping displays. If another resource handles seatbelts, set `Config.Seatbelt.enabled = false` here so both scripts do not compete for the exit control.

Fuel works automatically when your fuel script synchronizes FiveM's native vehicle fuel level. If its fuel value differs or the meter shows `—`, see the **Fuel integration** section in `README.md` for the provider function and full-tank capacity setting.

## Updating from an older version

Replace `fxmanifest.lua`, `client.lua`, and the **whole `web` folder** together, then run `restart zz-speedomter`. Keep your custom `config.lua`; the detailed dial now renders at approximately 280 × 327 with `Config.Scale = 1.0`. Set `Config.Scale = 0.85` if you want it smaller still. Optional `Config.MaxRpm = 9000` controls the restored RPM numbers and readout; older configs without this field use 9000 automatically.

Version 1.1.0 removes the dark color scheme responsible for the grey embedded-browser canvas. Do not mix old CSS or HTML with the updated files. If the previous screen persists after restarting, reconnect and confirm that only the updated copy of the resource is running.

Version 1.2.0 restores the earlier dial style and adds smooth frame-based RPM interpolation. Update `client.lua` as well as the UI to receive the finer RPM readings. No polling interval change is needed.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Resource cannot be found | Folder name is `zz-speedomter`; run `refresh`; check for double nesting. |
| No HUD | Resource is started; enter the driver's seat of a road vehicle, close the pause menu, and check the client F8 console for errors. |
| Two speedometers | Disable the old speedometer component in its own settings. |
| Cannot exit the vehicle | Press B to unbuckle; inspect other seatbelt resources if the problem remains. |
| Belt key does nothing | Check the player's saved FiveM key mapping; it overrides the configured default. |
| Fuel is wrong | Confirm the provider and `Config.Fuel.capacity`; start a custom provider before this HUD. |
| Grey screen over the game | Replace the complete `web` folder with version 1.1.0 or newer; restart the resource and reconnect if necessary. |

For performance verification, open the client **F8 console** and run `resmon 1`. Compare `zz-speedomter` while on foot, driving, and belted. Run `resmon 0` when finished. The resource is designed to minimize work, but actual CPU time and visual integration must be checked on your server and hardware.
