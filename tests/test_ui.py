"""Exercise the shipped UI in Chromium. Requires Python Playwright, not npm."""
import functools
import http.server
import os
from pathlib import Path
import shutil
import threading
import unittest

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
        self.page.goto(self.url)

    def tearDown(self):
        self.page.close()
        self.assertEqual(self.errors, [])

    def send(self, **data):
        self.page.evaluate("data => window.dispatchEvent(new MessageEvent('message', {data}))", data)

    def test_hidden_transparent_default_and_no_runtime_requests(self):
        self.assertTrue(self.page.locator("#hud").is_hidden())
        self.assertTrue(self.page.locator("#preview").is_hidden())
        self.assertEqual(self.page.locator("body").evaluate("el => getComputedStyle(el).backgroundColor"), "rgba(0, 0, 0, 0)")
        requests = []
        self.page.on("request", lambda request: requests.append(request.url))
        self.page.wait_for_timeout(1100)
        self.assertEqual(requests, [])

    def test_telemetry_deltas_warning_states_and_visibility(self):
        self.send(action="visibility", visible=True)
        self.send(action="telemetry", speed=199, rpm=94, gear="4", fuel=12,
                  engine=True, engineWarning=False, lights=2, belt=True, beltAvailable=True)
        self.assertEqual(self.page.locator("#speed").inner_text(), "199")
        self.assertEqual(self.page.locator("#rpm-value").inner_text(), "8.5")
        self.assertEqual(self.page.locator("#gear").inner_text(), "4")
        self.assertEqual(self.page.locator("#fuel-value").inner_text(), "12%")
        self.assertTrue(self.page.locator("#fuel-warning").is_visible())
        self.assertIn("redline", self.page.locator("#hud").get_attribute("class"))
        self.assertEqual(self.page.locator("#lights").get_attribute("aria-label"), "High beams on")
        self.send(action="telemetry", speed=202)
        self.assertEqual(self.page.locator("#gear").inner_text(), "4")
        self.assertEqual(self.page.locator("#fuel-value").inner_text(), "12%")
        self.send(action="telemetry", rpm=20, fuel=50, belt=False, engineWarning=True, lights=0)
        self.assertTrue(self.page.locator("#fuel-warning").is_hidden())
        self.assertNotIn("redline", self.page.locator("#hud").get_attribute("class"))
        self.assertEqual(self.page.locator("#engine").get_attribute("aria-label"), "Engine damaged")
        self.assertEqual(self.page.locator("#belt").get_attribute("aria-label"), "Seatbelt unfastened")
        self.send(action="visibility", visible=False)
        self.assertTrue(self.page.locator("#hud").is_hidden())

    def test_config_and_safe_zone_layout(self):
        self.send(action="config", unit="mph", maxRpm=12000, scale=1.2, right=40, bottom=35,
                  safeZone=.05, accent="#aabbcc", lowFuel=30, fuelEnabled=False)
        self.send(action="visibility", visible=True)
        self.send(action="telemetry", rpm=50, beltAvailable=False)
        self.assertEqual(self.page.locator("#unit").inner_text(), "MPH")
        self.assertEqual(self.page.locator("#rpm-value").inner_text(), "6.0")
        self.assertEqual(self.page.locator(".tick-label").last.text_content(), "12")
        self.assertEqual(self.page.locator("#ticks line").count(), 37)
        self.assertTrue(self.page.locator("#fuel").is_hidden())
        self.assertTrue(self.page.locator("#belt").is_hidden())
        self.assertEqual(self.page.locator("html").evaluate("e => getComputedStyle(e).getPropertyValue('--accent')"), "#aabbcc")
        box = self.page.locator("#hud").bounding_box()
        self.assertAlmostEqual(box["x"] + box["width"], 1920 - 40 - 96, delta=1)
        self.assertAlmostEqual(box["y"] + box["height"], 1080 - 35 - 54, delta=1)

    def test_repeated_config_does_not_rebuild_static_dial(self):
        self.page.evaluate("window.originalTick = document.querySelector('#ticks line')")
        self.send(action="config", maxRpm=9000)
        self.send(action="config", maxRpm=9000, safeZone=.1)
        self.assertTrue(self.page.evaluate("window.originalTick === document.querySelector('#ticks line')"))
        self.send(action="config", maxRpm=12000)
        self.assertFalse(self.page.evaluate("window.originalTick === document.querySelector('#ticks line')"))

    def test_duplicate_updates_do_not_mutate_the_dom(self):
        self.send(action="visibility", visible=True)
        telemetry = dict(action="telemetry", speed=124, rpm=52, gear="4", fuel=68,
                         engine=True, engineWarning=False, lights=1, belt=True, beltAvailable=True)
        config = dict(action="config", unit="kmh", maxRpm=9000, scale=1,
                      right=32, bottom=28, safeZone=.05, accent="#62f5bb", fuelEnabled=True)
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
        for selector in ["#rpm-arc", "#fuel-fill"]:
            self.assertEqual(self.page.locator(selector).evaluate("e => getComputedStyle(e).transitionDuration"), "0s")

    def test_unknown_fuel_and_malformed_input(self):
        self.send(action="visibility", visible=True)
        self.send(action="telemetry", fuel=-1, gear="<img>", speed=-20, rpm=999)
        self.assertEqual(self.page.locator("#fuel-value").inner_text(), "—")
        self.assertTrue(self.page.locator("#fuel-warning").is_hidden())
        self.assertEqual(self.page.locator("#speed").inner_text(), "0")
        self.assertEqual(self.page.locator("#gear").inner_text(), "N")
        self.assertEqual(self.page.locator("#rpm-arc").get_attribute("stroke-dasharray"), "75 100")
        self.send(action="telemetry", fuel=400, speed=4000)
        self.assertEqual(self.page.locator("#fuel-value").inner_text(), "100%")
        self.assertEqual(self.page.locator("#speed").inner_text(), "999")
        self.page.evaluate("window.postMessage(null, '*')")

    def test_preview_controls_and_units(self):
        self.page.goto(self.url + "/?preview")
        self.assertTrue(self.page.locator("#preview").is_visible())
        self.assertEqual(self.page.locator("#speed").inner_text(), "124")
        self.page.locator('[data-preset="redline"]').click()
        self.assertEqual(self.page.locator("#speed").inner_text(), "248")
        self.assertTrue(self.page.locator("#fuel-warning").is_visible())
        self.page.locator("#demo-unit").click()
        self.assertEqual(self.page.locator("#speed").inner_text(), "154")
        self.assertEqual(self.page.locator("#unit").inner_text(), "MPH")
        self.page.locator('[data-preset="cruise"]').click()
        self.assertEqual(self.page.locator("#speed").inner_text(), "77")
        self.page.locator("#demo-belt").click()
        self.assertEqual(self.page.locator("#belt").get_attribute("aria-label"), "Seatbelt unfastened")
        self.page.locator('[data-preset="parked"]').click()
        self.assertEqual(self.page.locator("#speed").inner_text(), "0")
        self.assertEqual(self.page.locator("#gear").inner_text(), "N")

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
        self.assertTrue(self.page.locator("#preview").is_hidden())
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
                self.send(action="telemetry", speed=999, rpm=94, gear="R", fuel=3,
                          beltAvailable=True, belt=False, engineWarning=True, lights=2)
                self.page.wait_for_timeout(180)
                arc_color = self.page.locator("#rpm-arc").evaluate("e => getComputedStyle(e).stroke")
                self.assertEqual(arc_color, "rgb(255, 98, 107)")
                speed = self.page.locator("#speed").bounding_box()
                gear = self.page.locator(".gear-block").bounding_box()
                self.assertLess(speed["y"] + speed["height"], gear["y"])
                wordmark = self.page.locator(".wordmark").bounding_box()
                icons = self.page.locator(".indicators").bounding_box()
                self.assertLess(wordmark["x"] + wordmark["width"], icons["x"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
