(() => {
  'use strict';

  const $ = (id) => document.getElementById(id);
  const hud = $('hud');
  const root = document.documentElement;
  const hasNui = typeof window.GetParentResourceName === 'function';
  const preview = !hasNui && new URLSearchParams(location.search).has('preview');
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

  function indicator(element, active, warning, high, label) {
    element.classList.toggle('active', active);
    element.classList.toggle('warning', warning);
    element.classList.toggle('high', high);
    element.setAttribute('aria-label', label);
  }

  function render(delta) {
    if ('speed' in delta) refs.speed.textContent = String(clamp(Math.round(number(delta.speed, 0)), 0, 999));
    if ('rpm' in delta) {
      state.rpm = clamp(number(delta.rpm, 0), 0, 100);
      refs['rpm-arc'].setAttribute('stroke-dasharray', `${state.rpm * .75} 100`);
      refs['rpm-value'].textContent = (state.rpm / 100 * config.maxRpm / 1000).toFixed(1);
      hud.classList.toggle('redline', state.rpm >= 85);
    }
    if ('gear' in delta) refs.gear.textContent = /^[NR0-9]$|^1[0-9]$/.test(String(delta.gear)) ? String(delta.gear) : 'N';
    if ('engine' in delta || 'engineWarning' in delta) {
      indicator(refs.engine, state.engine && !state.engineWarning, state.engineWarning, false,
        state.engineWarning ? 'Engine damaged' : state.engine ? 'Engine running' : 'Engine off');
    }
    if ('belt' in delta || 'beltAvailable' in delta) {
      refs.belt.hidden = !state.beltAvailable;
      indicator(refs.belt, state.belt, !state.belt, false, state.belt ? 'Seatbelt fastened' : 'Seatbelt unfastened');
    }
    if ('lights' in delta) {
      indicator(refs.lights, state.lights === 1, false, state.lights === 2,
        state.lights === 2 ? 'High beams on' : state.lights === 1 ? 'Headlights on' : 'Lights off');
    }
    if ('fuel' in delta) {
      const raw = number(delta.fuel, -1);
      const fuel = raw < 0 ? -1 : clamp(Math.round(raw), 0, 100);
      const low = fuel >= 0 && fuel <= config.lowFuel;
      refs['fuel-value'].textContent = fuel < 0 ? '—' : `${fuel}%`;
      refs['fuel-fill'].style.transform = `scaleX(${Math.max(0, fuel) / 100})`;
      refs.fuel.classList.toggle('low', low);
      refs['fuel-warning'].hidden = !low;
    }
  }

  function configure(data) {
    if ('unit' in data) config.unit = data.unit === 'mph' ? 'mph' : 'kmh';
    refs.unit.textContent = config.unit === 'mph' ? 'MPH' : 'KM/H';
    if ('scale' in data) root.style.setProperty('--scale', clamp(number(data.scale, 1), .65, 1.5));
    for (const key of ['right', 'bottom']) {
      if (key in data) root.style.setProperty(`--${key}`, `${clamp(number(data[key], 0), 0, 4000)}px`);
    }
    if ('safeZone' in data) {
      const inset = clamp(number(data.safeZone, 0), 0, .1) * 100;
      root.style.setProperty('--safe-x', `${inset}vw`);
      root.style.setProperty('--safe-y', `${inset}vh`);
    }
    if (typeof data.accent === 'string' && /^#[\da-f]{6}$/i.test(data.accent)) root.style.setProperty('--accent', data.accent);
    if ('maxRpm' in data) {
      const maxRpm = clamp(number(data.maxRpm, 9000), 1000, 20000);
      if (maxRpm !== config.maxRpm) {
        config.maxRpm = maxRpm;
        drawTicks();
      }
    }
    if ('lowFuel' in data) config.lowFuel = clamp(number(data.lowFuel, 20), 0, 100);
    if ('fuelEnabled' in data) config.fuelEnabled = data.fuelEnabled === true;
    refs.fuel.hidden = !config.fuelEnabled;
    render(state);
  }

  function receive(data) {
    if (!data || typeof data !== 'object') return;
    if (data.action === 'visibility') hud.hidden = data.visible !== true;
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

  if (hasNui) {
    // Handshake after DOM initialization prevents lost initial configuration.
    // Retries are bounded and only cover resource startup, never telemetry.
    const ready = async (attempt = 0) => {
      try {
        const response = await fetch(`https://${window.GetParentResourceName()}/ready`, {
          method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}',
        });
        if (!response.ok) throw new Error('NUI not ready');
      } catch {
        if (attempt < 4) setTimeout(() => ready(attempt + 1), 500 * (attempt + 1));
      }
    };
    ready();
  }

  if (preview) {
    document.body.classList.add('preview-mode');
    $('preview').hidden = false;
    hud.hidden = false;
    const presets = {
      cruise: { speed: 124, rpm: 52, gear: '4', fuel: 68, engine: true, engineWarning: false, belt: true, beltAvailable: true, lights: 0 },
      redline: { speed: 248, rpm: 94, gear: '6', fuel: 12, engine: true, engineWarning: false, belt: true, beltAvailable: true, lights: 2 },
      parked: { speed: 0, rpm: 0, gear: 'N', fuel: 43, engine: false, engineWarning: false, belt: false, beltAvailable: true, lights: 0 },
    };
    const demo = (data) => {
      receive({ action: 'telemetry', ...data });
      $('demo-speed').value = state.speed;
      $('demo-rpm').value = state.rpm;
      $('demo-speed-label').value = state.speed;
      $('demo-rpm-label').value = `${(state.rpm / 100 * config.maxRpm / 1000).toFixed(1)}k`;
      $('demo-belt').textContent = `Belt: ${state.belt ? 'on' : 'off'}`;
      $('demo-belt').setAttribute('aria-pressed', state.belt);
      $('demo-lights').textContent = `Lights: ${['off', 'on', 'high'][state.lights]}`;
      $('demo-lights').setAttribute('aria-pressed', state.lights > 0);
    };
    document.querySelectorAll('[data-preset]').forEach((button) => button.addEventListener('click', () => {
      document.querySelectorAll('[data-preset]').forEach((item) => item.classList.toggle('selected', item === button));
      const preset = presets[button.dataset.preset];
      demo({ ...preset, speed: Math.round(preset.speed * (config.unit === 'mph' ? .6213711922 : 1)) });
    }));
    $('demo-speed').addEventListener('input', (event) => demo({ speed: Number(event.target.value) }));
    $('demo-rpm').addEventListener('input', (event) => demo({ rpm: Number(event.target.value) }));
    $('demo-belt').addEventListener('click', () => demo({ belt: !state.belt }));
    $('demo-lights').addEventListener('click', () => demo({ lights: (state.lights + 1) % 3 }));
    $('demo-unit').addEventListener('click', () => {
      const unit = config.unit === 'kmh' ? 'mph' : 'kmh';
      const speed = Math.round(state.speed * (unit === 'mph' ? .6213711922 : 1.609344));
      configure({ unit });
      $('demo-speed').max = unit === 'mph' ? 200 : 320;
      $('demo-unit').textContent = unit === 'mph' ? 'MPH → KM/H' : 'KM/H → MPH';
      demo({ speed });
    });
    demo(presets.cruise);
  }
})();
