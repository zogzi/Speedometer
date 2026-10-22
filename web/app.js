(() => {
  'use strict';

  const $ = (id) => document.getElementById(id);
  const hud = $('hud');
  const root = document.documentElement;
  const hasNui = typeof window.GetParentResourceName === 'function';
  // This resource has no browser demo or query-string activation path.
  if (!hasNui) return;
  const state = {
    speed: 0, rpm: 0, gear: 'N', engineWarning: false,
    lights: 0, fuel: -1, belt: false, beltAvailable: true,
  };
  const config = { unit: 'kmh', lowFuel: 20, fuelEnabled: true };
  const telemetryKeys = Object.keys(state);
  const clamp = (value, min, max) => Math.min(max, Math.max(min, value));
  const number = (value, fallback) => typeof value === 'number' && Number.isFinite(value) ? value : fallback;
  const refs = Object.fromEntries([
    'speed', 'unit', 'gear', 'rpm-arc', 'engine', 'belt', 'lights', 'indicators',
    'fuel', 'fuel-value', 'fuel-fill',
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

  function render(delta) {
    if ('speed' in delta) text(refs.speed, String(clamp(Math.round(number(delta.speed, 0)), 0, 999)));
    if ('rpm' in delta) {
      state.rpm = clamp(number(delta.rpm, 0), 0, 100);
      attribute(refs['rpm-arc'], 'stroke-dasharray', `${state.rpm * .75} 100`);
      hud.classList.toggle('redline', state.rpm >= 85);
    }
    if ('gear' in delta) text(refs.gear, /^[NR0-9]$|^1[0-9]$/.test(String(delta.gear)) ? String(delta.gear) : 'N');
    if ('engineWarning' in delta) {
      hidden(refs.engine, !state.engineWarning);
    }
    if ('belt' in delta || 'beltAvailable' in delta) {
      hidden(refs.belt, !state.beltAvailable || state.belt);
      attribute(refs.belt, 'aria-label', state.belt ? 'Seatbelt fastened' : 'Seatbelt unfastened');
    }
    if ('lights' in delta) {
      hidden(refs.lights, state.lights !== 1 && state.lights !== 2);
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
      attribute(refs.fuel, 'aria-label', fuel < 0 ? 'Fuel unknown' : `Fuel ${fuel} percent${low ? ', low' : ''}`);
    }
    hidden(refs.indicators, refs.engine.hidden && refs.belt.hidden && refs.lights.hidden);
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
    if ('lowFuel' in data) config.lowFuel = clamp(number(data.lowFuel, 20), 0, 100);
    if ('fuelEnabled' in data) config.fuelEnabled = data.fuelEnabled === true;
    hidden(refs.fuel, !config.fuelEnabled);
    render(state);
  }

  function receive(data) {
    if (!data || typeof data !== 'object') return;
    if (data.action === 'visibility') hidden(hud, data.visible !== true);
    if (data.action === 'config') configure(data);
    if (data.action === 'telemetry') {
      // Only copy known fields; messages never supply HTML or execute code.
      for (const key of telemetryKeys) if (key in data) state[key] = data[key];
      render(data);
    }
  }

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
