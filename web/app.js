(() => {
  'use strict';

  const $ = (id) => document.getElementById(id);
  const hud = $('hud');
  const root = document.documentElement;
  const hasNui = typeof window.GetParentResourceName === 'function';
  // This resource has no browser demo or query-string activation path.
  if (!hasNui) return;
  const state = {
    speed: 0, rpm: 0, gear: 'N', engine: false, engineWarning: false,
    lights: 0, fuel: -1, belt: false, beltAvailable: true,
  };
  const config = { unit: 'kmh', maxRpm: 9000, lowFuel: 20, fuelEnabled: true };
  const telemetryKeys = Object.keys(state);
  const clamp = (value, min, max) => Math.min(max, Math.max(min, value));
  const number = (value, fallback) => typeof value === 'number' && Number.isFinite(value) ? value : fallback;
  const refs = Object.fromEntries([
    'speed', 'unit', 'gear', 'rpm-arc', 'rpm-value', 'engine', 'belt', 'lights',
    'fuel', 'fuel-value', 'fuel-fill', 'fuel-warning',
  ].map((id) => [id, $(id)]));

  // Avoid replacing text nodes or dirtying attributes when the display is unchanged.
  function text(element, value) {
    if (element.textContent !== value) element.textContent = value;
  }

  function attribute(element, name, value) {
    if (element.getAttribute(name) !== value) element.setAttribute(name, value);
  }

  function hidden(element, value) {
    if (element.hidden !== value) element.hidden = value;
  }

  function style(name, value) {
    const css = String(value);
    if (root.style.getPropertyValue(name) !== css) root.style.setProperty(name, css);
  }

  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  let rpmTarget = 0;
  let rpmDisplay = 0;
  let rpmFrame = 0;
  let rpmTime = 0;

  function paintRpm() {
    attribute(refs['rpm-arc'], 'stroke-dasharray', `${Number((rpmDisplay * .75).toFixed(3))} 100`);
  }

  function stopRpm() {
    if (rpmFrame) cancelAnimationFrame(rpmFrame);
    rpmFrame = 0;
    rpmTime = 0;
  }

  function stepRpm(now) {
    rpmFrame = 0;
    if (hud.hidden || document.hidden) {
      rpmDisplay = rpmTarget;
      rpmTime = 0;
      return;
    }
    // Time-based damping keeps the same response at 30, 60, or 144 Hz.
    // Retargeting changes only the destination, never the current position.
    const elapsed = Math.max(0, now - rpmTime);
    rpmTime = now;
    rpmDisplay += (rpmTarget - rpmDisplay) * (1 - Math.exp(-elapsed / 60));
    const settled = Math.abs(rpmTarget - rpmDisplay) < .015;
    if (settled) rpmDisplay = rpmTarget;
    paintRpm();
    if (!settled) rpmFrame = requestAnimationFrame(stepRpm);
    else rpmTime = 0;
  }

  function setRpmTarget(value) {
    rpmTarget = value;
    if (hud.hidden || document.hidden || reducedMotion.matches) {
      stopRpm();
      rpmDisplay = rpmTarget;
      if (!hud.hidden && !document.hidden) paintRpm();
      return;
    }
    if (!rpmFrame && Math.abs(rpmTarget - rpmDisplay) >= .015) {
      rpmTime = performance.now();
      rpmFrame = requestAnimationFrame(stepRpm);
    }
  }

  function syncRpmVisibility() {
    if (hud.hidden || document.hidden) {
      stopRpm();
      rpmDisplay = rpmTarget;
    } else if (!rpmFrame) {
      rpmDisplay = rpmTarget;
      paintRpm();
    }
  }

  document.addEventListener('visibilitychange', syncRpmVisibility);
  reducedMotion.addEventListener('change', () => setRpmTarget(rpmTarget));

  function drawTicks() {
    const ns = 'http://www.w3.org/2000/svg';
    const group = $('ticks');
    const fragment = document.createDocumentFragment();
    for (let i = 0; i <= 36; i++) {
      const angle = (135 + i * 7.5) * Math.PI / 180;
      const major = i % 4 === 0;
      const point = (radius) => [160 + Math.cos(angle) * radius, 160 + Math.sin(angle) * radius];
      const start = point(major ? 116 : 120);
      const end = point(125);
      const line = document.createElementNS(ns, 'line');
      line.setAttribute('x1', start[0]); line.setAttribute('y1', start[1]);
      line.setAttribute('x2', end[0]); line.setAttribute('y2', end[1]);
      line.setAttribute('class', `tick${major ? ' major' : ''}`);
      fragment.append(line);
      if (major) {
        const [x, y] = point(103);
        const text = document.createElementNS(ns, 'text');
        text.setAttribute('x', x); text.setAttribute('y', y);
        text.setAttribute('class', `tick-label${i >= 32 ? ' red' : ''}`);
        text.textContent = String(Math.round(i / 36 * config.maxRpm / 1000 * 10) / 10);
        fragment.append(text);
      }
    }
    group.replaceChildren(fragment);
  }

  function render(delta) {
    if ('speed' in delta) text(refs.speed, String(clamp(Math.round(number(delta.speed, 0)), 0, 999)));
    if ('rpm' in delta) {
      state.rpm = clamp(number(delta.rpm, 0), 0, 100);
      setRpmTarget(state.rpm);
      text(refs['rpm-value'], (state.rpm / 100 * config.maxRpm / 1000).toFixed(1));
      hud.classList.toggle('redline', state.rpm >= 85);
    }
    if ('gear' in delta) text(refs.gear, /^[NR0-9]$|^1[0-9]$/.test(String(delta.gear)) ? String(delta.gear) : 'N');
    if ('engine' in delta || 'engineWarning' in delta) {
      refs.engine.classList.toggle('active', state.engine && !state.engineWarning);
      refs.engine.classList.toggle('warning', state.engineWarning);
      attribute(refs.engine, 'aria-label', state.engineWarning ? 'Engine damaged' : state.engine ? 'Engine running' : 'Engine off');
    }
    if ('belt' in delta || 'beltAvailable' in delta) {
      hidden(refs.belt, !state.beltAvailable);
      refs.belt.classList.toggle('active', state.belt);
      refs.belt.classList.toggle('warning', !state.belt);
      attribute(refs.belt, 'aria-label', state.belt ? 'Seatbelt fastened' : 'Seatbelt unfastened');
    }
    if ('lights' in delta) {
      refs.lights.classList.toggle('active', state.lights === 1);
      refs.lights.classList.toggle('high', state.lights === 2);
      attribute(refs.lights, 'aria-label',
        state.lights === 2 ? 'High beams on' : state.lights === 1 ? 'Headlights on' : 'Lights off');
    }
    if ('fuel' in delta) {
      const raw = number(delta.fuel, -1);
      const fuel = raw < 0 ? -1 : clamp(Math.round(raw), 0, 100);
      const low = fuel >= 0 && fuel <= config.lowFuel;
      text(refs['fuel-value'], fuel < 0 ? '—' : `${fuel}%`);
      const transform = `scaleX(${Math.max(0, fuel) / 100})`;
      if (refs['fuel-fill'].style.transform !== transform) refs['fuel-fill'].style.transform = transform;
      refs.fuel.classList.toggle('low', low);
      hidden(refs['fuel-warning'], !low);
      attribute(refs.fuel, 'aria-label', fuel < 0 ? 'Fuel unknown' : `Fuel ${fuel} percent${low ? ', low' : ''}`);
    }
  }

  function configure(data) {
    if ('unit' in data) config.unit = data.unit === 'mph' ? 'mph' : 'kmh';
    text(refs.unit, config.unit === 'mph' ? 'MPH' : 'KM/H');
    if ('scale' in data) style('--scale', clamp(number(data.scale, 1), .65, 1.5));
    for (const key of ['right', 'bottom']) {
      if (key in data) style(`--${key}`, `${clamp(number(data[key], 0), 0, 4000)}px`);
    }
    if ('safeZone' in data) {
      const inset = clamp(number(data.safeZone, 0), 0, .1) * 100;
      style('--safe-x', `${inset}vw`);
      style('--safe-y', `${inset}vh`);
    }
    if (typeof data.accent === 'string' && /^#[\da-f]{6}$/i.test(data.accent)) style('--accent', data.accent);
    if ('maxRpm' in data) {
      const maxRpm = clamp(number(data.maxRpm, 9000), 1000, 20000);
      if (maxRpm !== config.maxRpm) {
        config.maxRpm = maxRpm;
        drawTicks();
      }
    }
    if ('lowFuel' in data) config.lowFuel = clamp(number(data.lowFuel, 20), 0, 100);
    if ('fuelEnabled' in data) config.fuelEnabled = data.fuelEnabled === true;
    hidden(refs.fuel, !config.fuelEnabled);
    render(state);
  }

  function receive(data) {
    if (!data || typeof data !== 'object') return;
    if (data.action === 'visibility') {
      hidden(hud, data.visible !== true);
      syncRpmVisibility();
    }
    if (data.action === 'config') configure(data);
    if (data.action === 'telemetry') {
      // Only copy known fields; messages never supply HTML or execute code.
      for (const key of telemetryKeys) if (key in data) state[key] = data[key];
      render(data);
    }
  }

  drawTicks();
  render(state);
  window.addEventListener('message', (event) => receive(event.data));

  // Handshake after DOM initialization prevents lost initial configuration.
  // Retries are bounded and only cover resource startup, never telemetry.
  const ready = async (attempt = 0) => {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 2000);
    try {
      const response = await fetch(`https://${window.GetParentResourceName()}/ready`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}', signal: controller.signal,
      });
      if (!response.ok) throw new Error('NUI not ready');
    } catch {
      if (attempt < 4) setTimeout(() => ready(attempt + 1), 500 * (attempt + 1));
    } finally {
      clearTimeout(timeout);
    }
  };
  ready();
})();
