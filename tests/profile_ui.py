"""Local Chromium work counts, not a FiveM resmon/GPU benchmark.

Run: python tests/profile_ui.py
Requires the same development dependencies as test_ui.py. The fixtures serve the
unchanged production UI and inject FiveM messages externally. No harness ships in
the resource. Output is JSON for reproducible comparisons on the same machine.
"""
import json
import time

from test_ui import HudTests


def main():
    HudTests.setUpClass()
    test = HudTests()
    test.setUp()
    page = test.page
    try:
        page.set_viewport_size({"width": 1920, "height": 1080})
        page.evaluate("""() => {
            window.profileFrames = 0;
            const raf = window.requestAnimationFrame.bind(window);
            window.requestAnimationFrame = cb => raf(t => { profileFrames++; cb(t); });
        }""")
        session = page.context.new_cdp_session(page)
        session.send("Performance.enable")

        def metrics():
            return {item["name"]: item["value"]
                    for item in session.send("Performance.getMetrics")["metrics"]}

        results = []
        for scenario in ["hidden", "stable", "rpm_only", "driving"]:
            test.send(action="visibility", visible=scenario != "hidden")
            test.send(action="telemetry", speed=124, rpm=52, gear="4", engine=True,
                      belt=True, beltAvailable=True, lights=1)
            page.wait_for_timeout(1200)  # Let the initial transition settle.
            frames = page.evaluate("profileFrames")
            before = metrics()
            start = time.perf_counter()
            if scenario in ["rpm_only", "driving"]:
                page.evaluate("""scenario => {
                    let tick = 0;
                    window.profileTimer = setInterval(() => {
                        tick++;
                        const data = {action:'telemetry', rpm:20+(tick%120)*.58};
                        if (scenario === 'driving') data.speed = 40+tick/6;
                        window.dispatchEvent(new MessageEvent('message', {data}));
                    }, 16);
                }""", scenario)
            page.wait_for_timeout(3000)
            if scenario in ["rpm_only", "driving"]:
                page.evaluate("clearInterval(profileTimer)")
            after = metrics()
            elapsed = time.perf_counter() - start
            row = {"scenario": scenario, "wall_seconds": round(elapsed, 3),
                   "gauge_animation_callbacks": page.evaluate("profileFrames") - frames}
            for key in ["TaskDuration", "ScriptDuration", "LayoutDuration", "RecalcStyleDuration"]:
                row[key + "_ms_per_second"] = round((after[key] - before[key]) * 1000 / elapsed, 3)
            for key in ["LayoutCount", "RecalcStyleCount"]:
                row[key] = after[key] - before[key]
            results.append(row)
        print(json.dumps({"browser": HudTests.browser.version,
                          "viewport": "1920x1080", "sample_ms": 16,
                          "results": results}, indent=2))
    finally:
        test.tearDown()
        HudTests.tearDownClass()


if __name__ == "__main__":
    main()
