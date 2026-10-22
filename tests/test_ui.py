"""Exercise the shipped UI in Chromium. Requires Python Playwright, not npm."""
import functools
import http.server
import io
import os
from pathlib import Path
import shutil
import threading
import unittest

from PIL import Image
from playwright.sync_api import sync_playwright

WEB = Path(__file__).resolve().parents[1] / "web"


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


class HudTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = http.server.ThreadingHTTPServer(
            ("127.0.0.1", 0), functools.partial(QuietHandler, directory=str(WEB))
        )
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.url = f"http://127.0.0.1:{cls.server.server_port}"
        cls.playwright = sync_playwright().start()
        binary = os.environ.get("CHROMIUM_PATH") or shutil.which("chromium") or shutil.which("google-chrome")
        options = {"headless": True}
        if binary:
            options["executable_path"] = binary
        cls.browser = cls.playwright.chromium.launch(**options)

    @classmethod
    def tearDownClass(cls):
        cls.browser.close()
        cls.playwright.stop()
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()

    def setUp(self):
        self.page = self.browser.new_page(viewport={"width": 1920, "height": 1080})
        self.errors = []
        self.page.on("pageerror", lambda error: self.errors.append(str(error)))
        self.page.add_init_script("window.GetParentResourceName = () => 'zz-speedomter'")
        self.page.route("https://zz-speedomter/ready", lambda route: route.fulfill(
            status=200, content_type="application/json", body='{"ok":true}',
            headers={"Access-Control-Allow-Origin": "*"}))
        # Finish the initial handshake before a test replaces its route or reloads.
        # Otherwise an old in-flight response can satisfy the next expectation.
        with self.page.expect_response("https://zz-speedomter/ready") as ready:
            self.page.goto(self.url)
        self.assertTrue(ready.value.ok)

    def tearDown(self):
        self.page.close()
        self.assertEqual(self.errors, [])

    def send(self, **data):
        self.page.evaluate("data => window.dispatchEvent(new MessageEvent('message', {data}))", data)

    def test_hidden_transparent_default_and_no_runtime_requests(self):
        self.assertTrue(self.page.locator("#hud").is_hidden())
        self.assertEqual(self.page.locator("#preview").count(), 0)
        self.assertEqual(self.page.locator("body").evaluate("el => getComputedStyle(el).backgroundColor"), "rgba(0, 0, 0, 0)")
        requests = []
        self.page.on("request", lambda request: requests.append(request.url))
        self.page.wait_for_timeout(1100)
        self.assertEqual(requests, [])

    def test_telemetry_deltas_warning_states_and_visibility(self):
        self.send(action="visibility", visible=True)
        self.send(action="telemetry", speed=199, rpm=94, gear="4",
                  engine=True, engineWarning=False, lights=2, belt=True, beltAvailable=True)
        self.assertEqual(self.page.locator("#speed").inner_text(), "199")
        self.assertEqual(self.page.locator("#gear").inner_text(), "4")
        self.assertIn("redline", self.page.locator("#hud").get_attribute("class"))
        self.assertEqual(self.page.locator("#lights").get_attribute("aria-label"), "High beams on")
        self.send(action="telemetry", speed=202)
        self.assertEqual(self.page.locator("#gear").inner_text(), "4")
        self.send(action="telemetry", rpm=20, belt=False, engineWarning=True, lights=0)
        self.assertNotIn("redline", self.page.locator("#hud").get_attribute("class"))
        self.assertEqual(self.page.locator("#engine").get_attribute("aria-label"), "Engine damaged")
        self.assertEqual(self.page.locator("#belt").get_attribute("aria-label"), "Seatbelt unfastened")
        self.send(action="visibility", visible=False)
        self.assertTrue(self.page.locator("#hud").is_hidden())

    def test_config_and_safe_zone_layout(self):
        self.send(action="config", unit="mph", maxRpm=12000, scale=1.2, right=40, bottom=35,
                  safeZone=.05, accent="#aabbcc")
        self.send(action="visibility", visible=True)
        self.send(action="telemetry", rpm=50, beltAvailable=False)
        self.assertEqual(self.page.locator("#unit").inner_text(), "MPH")
        self.assertEqual(self.page.locator(".tick-label").count(), 10)
        self.assertTrue(self.page.locator("#belt").is_hidden())
        self.assertEqual(self.page.locator("html").evaluate("e => getComputedStyle(e).getPropertyValue('--accent')"), "#aabbcc")
        box = self.page.locator("#hud").bounding_box()
        self.assertAlmostEqual(box["x"] + box["width"], 1920 - 40 - 96, delta=1)
        self.assertAlmostEqual(box["y"] + box["height"], 1080 - 35 - 54, delta=1)

    def test_configuration_retains_the_static_dial(self):
        self.page.evaluate("window.originalArc = document.querySelector('#rpm-arc')")
        self.send(action="config", scale=1.2, safeZone=.1, accent="#abcdef")
        self.assertTrue(self.page.evaluate("window.originalArc === document.querySelector('#rpm-arc')"))
        self.assertEqual(self.page.locator(".dial circle").count(), 5)

    def test_duplicate_updates_do_not_mutate_the_dom(self):
        self.send(action="visibility", visible=True)
        telemetry = dict(action="telemetry", speed=124, rpm=52, gear="4",
                         engine=True, engineWarning=False, lights=1, belt=True, beltAvailable=True)
        config = dict(action="config", unit="kmh", scale=1,
                      right=32, bottom=28, safeZone=.05, accent="#62f5bb")
        self.send(**config)
        self.send(**telemetry)
        mutations = self.page.evaluate("""({telemetry, config}) => {
            const observer = new MutationObserver(() => {});
            observer.observe(document.documentElement, {subtree:true, attributes:true, childList:true, characterData:true});
            for (let i = 0; i < 1000; i++) {
                window.dispatchEvent(new MessageEvent('message', {data:telemetry}));
                window.dispatchEvent(new MessageEvent('message', {data:{action:'visibility', visible:true}}));
            }
            window.dispatchEvent(new MessageEvent('message', {data:config}));
            const records = observer.takeRecords().map(record => `${record.target.id}:${record.type}:${record.attributeName}`);
            observer.disconnect();
            return records;
        }""", {"telemetry": telemetry, "config": config})
        self.assertEqual(mutations, [])

    def test_reduced_motion_disables_gauge_transitions(self):
        self.page.emulate_media(reduced_motion="reduce")
        self.assertEqual(self.page.locator("#rpm-arc").evaluate("e => getComputedStyle(e).transitionDuration"), "0s")

    def install_rpm_clock(self):
        self.page.evaluate("""() => {
            const clock = {now:performance.now(), id:0, pending:new Map()};
            performance.now = () => clock.now;
            window.requestAnimationFrame = callback => {
                const id = ++clock.id;
                clock.pending.set(id, callback);
                return id;
            };
            window.cancelAnimationFrame = id => clock.pending.delete(id);
            clock.tick = ms => {
                clock.now += ms;
                const callbacks = [...clock.pending.values()];
                clock.pending.clear();
                callbacks.forEach(callback => callback(clock.now));
                return Number(document.querySelector('#rpm-arc').getAttribute('stroke-dasharray').split(' ')[0]);
            };
            window.rpmClock = clock;
        }""")

    def test_rpm_interpolates_retargets_and_stops_after_settling(self):
        self.install_rpm_clock()
        self.send(action="visibility", visible=True)
        self.send(action="telemetry", rpm=100)
        self.assertEqual(self.page.locator("#rpm-arc").get_attribute("stroke-dasharray"), "0 100")
        middle = self.page.evaluate("rpmClock.tick(50)")
        self.assertGreater(middle, 0)
        self.assertLess(middle, 75)
        self.send(action="telemetry", rpm=20)
        self.assertEqual(float(self.page.locator("#rpm-arc").get_attribute("stroke-dasharray").split()[0]), middle)
        self.assertEqual(self.page.evaluate("rpmClock.pending.size"), 1)
        after_retarget = self.page.evaluate("rpmClock.tick(16)")
        self.assertLess(after_retarget, middle)
        self.assertGreater(after_retarget, 15)
        self.page.evaluate("() => {for(let i=0;i<60;i++) rpmClock.tick(16)}")
        self.assertEqual(self.page.locator("#rpm-arc").get_attribute("stroke-dasharray"), "15 100")
        self.assertEqual(self.page.evaluate("rpmClock.pending.size"), 0)

    def test_rpm_response_matches_at_different_frame_rates(self):
        self.install_rpm_clock()
        results = []
        for rate in [30, 60, 144]:
            self.send(action="visibility", visible=False)
            self.send(action="telemetry", rpm=0)
            self.send(action="visibility", visible=True)
            self.send(action="telemetry", rpm=90)
            results.append(self.page.evaluate("""rate => {
                let elapsed = 0;
                let value;
                while (elapsed < 200) {
                    const step = Math.min(1000/rate, 200-elapsed);
                    value = rpmClock.tick(step);
                    elapsed += step;
                }
                return value;
            }""", rate))
        self.assertLess(max(results) - min(results), .002)

    def test_hidden_hud_cancels_rpm_animation_and_reduced_motion_snaps(self):
        self.install_rpm_clock()
        self.send(action="visibility", visible=True)
        self.send(action="telemetry", rpm=95)
        self.page.evaluate("rpmClock.tick(16)")
        self.assertEqual(self.page.evaluate("rpmClock.pending.size"), 1)
        self.send(action="visibility", visible=False)
        before = self.page.locator("#rpm-arc").get_attribute("stroke-dasharray")
        self.assertEqual(self.page.evaluate("rpmClock.pending.size"), 0)
        self.page.evaluate("rpmClock.tick(1000)")
        self.assertEqual(self.page.locator("#rpm-arc").get_attribute("stroke-dasharray"), before)
        self.send(action="visibility", visible=True)
        self.assertEqual(self.page.locator("#rpm-arc").get_attribute("stroke-dasharray"), "71.25 100")
        self.page.emulate_media(reduced_motion="reduce")
        self.send(action="telemetry", rpm=40)
        self.assertEqual(self.page.locator("#rpm-arc").get_attribute("stroke-dasharray"), "30 100")
        self.assertEqual(self.page.evaluate("rpmClock.pending.size"), 0)

    def test_rpm_animates_through_real_browser_frames(self):
        self.send(action="visibility", visible=True)
        samples = self.page.evaluate("""() => new Promise(resolve => {
            const values = [];
            window.dispatchEvent(new MessageEvent('message', {data:{action:'telemetry',rpm:100}}));
            const sample = () => {
                values.push(Number(document.querySelector('#rpm-arc').getAttribute('stroke-dasharray').split(' ')[0]));
                if(values.length < 16) requestAnimationFrame(sample);
                else resolve(values);
            };
            requestAnimationFrame(sample);
        })""")
        self.assertGreater(len(set(samples)), 8)
        self.assertEqual(samples, sorted(samples))
        # The first callback can share the scheduling frame's timestamp.
        self.assertTrue(all(0 <= value <= 75 for value in samples))
        self.assertGreater(samples[-1], samples[0])

    def test_background_document_stops_rpm_frames(self):
        self.install_rpm_clock()
        self.send(action="visibility", visible=True)
        self.send(action="telemetry", rpm=90)
        self.page.evaluate("rpmClock.tick(16)")
        self.page.evaluate("""() => {
            Object.defineProperty(document, 'hidden', {configurable:true, value:true});
            document.dispatchEvent(new Event('visibilitychange'));
        }""")
        self.assertEqual(self.page.evaluate("rpmClock.pending.size"), 0)

        before = self.page.locator("#rpm-arc").get_attribute("stroke-dasharray")
        self.page.evaluate("rpmClock.tick(1000)")
        self.assertEqual(self.page.locator("#rpm-arc").get_attribute("stroke-dasharray"), before)
        self.page.evaluate("""() => {
            Object.defineProperty(document, 'hidden', {configurable:true, value:false});
            document.dispatchEvent(new Event('visibilitychange'));
        }""")
        self.assertEqual(self.page.locator("#rpm-arc").get_attribute("stroke-dasharray"), "67.5 100")
        self.assertEqual(self.page.evaluate("rpmClock.pending.size"), 0)


    def test_lights_do_not_start_rpm_frames_or_repeat_dom_updates(self):
        self.install_rpm_clock()
        self.send(action="visibility", visible=True)
        for lights in [0, 1, 2]:
            with self.subTest(lights=lights):
                self.send(action="telemetry", lights=lights)
                self.assertEqual(self.page.evaluate("rpmClock.pending.size"), 0)
                records = self.page.evaluate("""lights => {
                    const observer = new MutationObserver(() => {});
                    observer.observe(document.querySelector('#hud'), {subtree:true, attributes:true, childList:true});
                    for(let i=0;i<1000;i++) {
                        window.dispatchEvent(new MessageEvent('message', {data:{action:'telemetry',lights}}));
                    }
                    const count = observer.takeRecords().length;
                    observer.disconnect();
                    return count;
                }""", lights)
                self.assertEqual(records, 0)
                self.assertEqual(self.page.evaluate("rpmClock.pending.size"), 0)

    def test_malformed_input_and_removed_footer(self):
        self.page.emulate_media(reduced_motion="reduce")
        self.send(action="visibility", visible=True)
        self.send(action="telemetry", fuel=-1, gear="<img>", speed=-20, rpm=999)
        self.assertEqual(self.page.locator("#speed").inner_text(), "0")
        self.assertEqual(self.page.locator("#gear").inner_text(), "N")
        self.assertEqual(self.page.locator("#rpm-arc").get_attribute("stroke-dasharray"), "75 100")
        self.send(action="telemetry", fuel=400, speed=4000)
        self.assertEqual(self.page.locator("#speed").inner_text(), "999")
        self.page.evaluate("window.postMessage(null, '*')")
        self.send(action="config", fuelEnabled=True, lowFuel=20)
        self.assertEqual(self.page.locator("#fuel, #icon-fuel, #rpm-value, .rpm-caption").count(), 0)

    def test_engine_icon_turns_red_when_damaged_and_green_when_repaired(self):
        self.send(action="visibility", visible=True)
        self.send(action="config", accent="#5566ff")
        self.send(action="telemetry", engine=True, engineWarning=False)
        color = lambda: self.page.locator("#engine").evaluate("e => getComputedStyle(e).color")
        self.assertEqual(color(), "rgb(98, 245, 187)")
        self.send(action="telemetry", engineWarning=True)
        self.assertEqual(color(), "rgb(255, 98, 107)")
        self.send(action="telemetry", engine=False)
        self.assertEqual(color(), "rgb(255, 98, 107)")
        self.send(action="telemetry", engine=True, engineWarning=False)
        self.assertEqual(color(), "rgb(98, 245, 187)")

    def test_outside_fivem_stays_inactive_even_with_preview_query(self):
        outside = self.browser.new_page()
        try:
            outside.goto(self.url + "/?preview")
            outside.evaluate("window.postMessage({action:'visibility',visible:true}, '*')")
            self.assertTrue(outside.locator("#hud").is_hidden())
            self.assertEqual(outside.locator("#preview, button, input").count(), 0)
            self.assertEqual(outside.locator("html").evaluate("e => getComputedStyle(e).colorScheme"), "normal")
        finally:
            outside.close()

    def test_original_status_row_reflects_vehicle_states(self):
        self.send(action="visibility", visible=True)
        self.send(action="telemetry", engine=True, engineWarning=False, beltAvailable=True, belt=True, lights=0)
        self.assertTrue(self.page.locator("#indicators").is_visible())
        self.assertIn("active", self.page.locator("#engine").get_attribute("class"))
        self.assertIn("active", self.page.locator("#belt").get_attribute("class"))
        self.assertEqual(self.page.locator("#lights").get_attribute("aria-label"), "Lights off")
        self.send(action="telemetry", belt=False)
        self.assertIn("warning", self.page.locator("#belt").get_attribute("class"))
        self.send(action="telemetry", beltAvailable=False, lights=2, engineWarning=True)
        self.assertTrue(self.page.locator("#belt").is_hidden())
        self.assertIn("damaged", self.page.locator("#engine").get_attribute("class"))
        self.assertIn("high", self.page.locator("#lights").get_attribute("class"))

    def test_default_hud_is_compact(self):
        self.send(action="visibility", visible=True)
        box = self.page.locator("#hud").bounding_box()
        self.assertLess(box["width"], 300)
        self.assertLess(box["height"], 330)
        self.assertEqual(self.page.locator(".wordmark").count(), 1)
        self.assertEqual(self.page.locator(".rpm-caption, .fuel, #rpm-value").count(), 0)
        self.assertEqual(self.page.locator(".tick-label").count(), 10)

    def test_embedded_canvas_does_not_paint_over_the_game(self):
        self.page.set_viewport_size({"width":1280, "height":720})
        self.page.set_content(f'''<html style="color-scheme:normal"><body style="margin:0;background:rgb(33,66,99)">
          <iframe src="{self.url}" style="position:fixed;inset:0;width:100%;height:100%;border:0;background:transparent"></iframe>
        </body></html>''')
        frame = self.page.frames[1]
        frame.wait_for_selector("#hud", state="attached")
        image = Image.open(io.BytesIO(self.page.screenshot())).convert("RGB")
        self.assertEqual(image.getextrema(), ((33,33), (66,66), (99,99)),
                         "The hidden embedded HUD must leave every background pixel unchanged")
        frame.evaluate("""() => {
            window.dispatchEvent(new MessageEvent('message', {data:{action:'visibility',visible:true}}));
            window.dispatchEvent(new MessageEvent('message', {data:{action:'telemetry',speed:124,rpm:52,gear:'4',fuel:68,belt:true}}));
        }""")
        self.assertTrue(frame.locator("#hud").is_visible())
        image = Image.open(io.BytesIO(self.page.screenshot())).convert("RGB")
        for point in [(0,0), (640,360), (0,719), (1279,0), (1279,719)]:
            self.assertEqual(image.getpixel(point), (33,66,99))
        frame.evaluate("window.dispatchEvent(new MessageEvent('message', {data:{action:'visibility',visible:false}}))")
        image = Image.open(io.BytesIO(self.page.screenshot())).convert("RGB")
        self.assertEqual(image.getextrema(), ((33,33), (66,66), (99,99)))

    def test_nui_handshake_and_no_preview_in_game(self):
        self.page.add_init_script("window.GetParentResourceName = () => 'zz-speedomter'")
        replies = []

        def ready(route):
            replies.append(route.request.post_data)
            route.fulfill(status=200, content_type="application/json", body='{"ok":true}',
                          headers={"Access-Control-Allow-Origin": "*"})

        self.page.route("https://zz-speedomter/ready", ready)
        self.page.goto(self.url + "/?preview")
        self.page.wait_for_timeout(100)
        self.assertEqual(replies, ["{}"])
        self.assertEqual(self.page.locator("#preview").count(), 0)
        self.assertNotIn("preview-mode", self.page.locator("body").get_attribute("class") or "")

    def test_nui_startup_recovers_from_a_stalled_handshake(self):
        self.page.add_init_script("window.GetParentResourceName = () => 'zz-speedomter'")
        attempts = []
        stalled = []

        def ready(route):
            attempts.append(route.request)
            if len(attempts) > 1:
                route.fulfill(status=200, content_type="application/json", body='{"ok":true}',
                              headers={"Access-Control-Allow-Origin": "*"})
            else:
                stalled.append(route)
            # The first request deliberately stays pending to simulate startup lag.

        self.page.route("https://zz-speedomter/ready", ready)
        with self.page.expect_response("https://zz-speedomter/ready", timeout=5000) as response:
            self.page.goto(self.url)
        stalled[0].abort()  # Release Playwright's route after the browser has timed it out.
        self.assertTrue(response.value.ok)
        self.assertEqual(len(attempts), 2)
        self.send(action="visibility", visible=True)
        self.send(action="telemetry", speed=124)
        self.assertEqual(self.page.locator("#speed").inner_text(), "124")

    def test_hud_fits_common_resolutions(self):
        self.send(action="visibility", visible=True)
        for width, height in [(1280, 720), (1920, 1080), (2560, 1080), (3840, 2160)]:
            with self.subTest(resolution=(width, height)):
                self.page.set_viewport_size({"width": width, "height": height})
                box = self.page.locator("#hud").bounding_box()
                self.assertGreaterEqual(box["x"], 0)
                self.assertGreaterEqual(box["y"], 0)
                self.assertLessEqual(box["x"] + box["width"], width)
                self.assertLessEqual(box["y"] + box["height"], height)

    def test_visual_states_and_scale_extremes(self):
        self.send(action="visibility", visible=True)
        self.page.set_viewport_size({"width": 1280, "height": 720})
        for scale in [.65, 1, 1.5]:
            with self.subTest(scale=scale):
                self.send(action="config", scale=scale, safeZone=.1)
                box = self.page.locator("#hud").bounding_box()
                self.assertGreaterEqual(box["x"], 0)
                self.assertGreaterEqual(box["y"], 0)
                self.send(action="telemetry", speed=999, rpm=94, gear="R",
                          beltAvailable=True, belt=False, engineWarning=True, lights=2)
                self.page.wait_for_timeout(180)
                arc_color = self.page.locator("#rpm-arc").evaluate("e => getComputedStyle(e).stroke")
                self.assertEqual(arc_color, "rgb(255, 98, 107)")
                speed = self.page.locator("#speed").bounding_box()
                gear = self.page.locator(".gear-block").bounding_box()
                self.assertLess(speed["y"] + speed["height"], gear["y"])
                icons = self.page.locator("#indicators").bounding_box()
                self.assertLess(icons["y"] + icons["height"], speed["y"])



if __name__ == "__main__":
    unittest.main(verbosity=2)
