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
    lights: 0, belt: false, beltAvailable: true,
  };
  const config = { unit: 'kmh', maxRpm: 9000 };
  const telemetryKeys = Object.keys(state);
  const clamp = (value, min, max) => Math.min(max, Math.max(min, value));
  const number = (value, fallback) => typeof value === 'number' && Number.isFinite(value) ? value : fallback;
  const refs = Object.fromEntries([
    'speed', 'unit', 'gear', 'rpm-arc', 'engine', 'belt', 'lights',
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
  // Both instruments use one clock and retain their velocity across packets.
  // The exact spring solution behaves consistently at different refresh rates.
  const gauges = {
    speed: { target: 0, display: 0, velocity: 0, maximum: 999 },
    rpm: { target: 0, display: 0, velocity: 0, maximum: 100 },
  };
  const gaugeNames = Object.keys(gauges);
  let animationFrame = null;
  let animationTime = 0;

  function paintGauges() {
    text(refs.speed, String(Math.round(gauges.speed.display)));
    attribute(refs['rpm-arc'], 'stroke-dasharray', `${Number((gauges.rpm.display * .75).toFixed(5))} 100`);
  }

  function stopAnimation() {
    if (animationFrame !== null) cancelAnimationFrame(animationFrame);
    animationFrame = null;
    animationTime = 0;
    for (const gauge of Object.values(gauges)) gauge.velocity = 0;
  }

  function advanceGauges(now) {
    // A message can arrive after this frame's timestamp. Never move time back.
    now = Math.max(now, animationTime);
    const elapsed = now - animationTime;
    animationTime = now;
    const frequency = .018;
    const decay = Math.exp(-frequency * elapsed);
    let settled = true;
    for (const gauge of Object.values(gauges)) {
      const offset = gauge.display - gauge.target;
      const coefficient = gauge.velocity + frequency * offset;
      const position = gauge.target + (offset + coefficient * elapsed) * decay;
      gauge.velocity = (gauge.velocity - frequency * coefficient * elapsed) * decay;
      gauge.display = clamp(position, 0, gauge.maximum);
      if (position !== gauge.display) gauge.velocity = 0;
      // Finish below a visible fraction of a digit or arc pixel.
      if (Math.abs(gauge.target - gauge.display) < .001 && Math.abs(gauge.velocity) < .0001) {
        gauge.display = gauge.target;
        gauge.velocity = 0;
      } else settled = false;
    }
    return settled;
  }

  function snapGauges() {
    stopAnimation();
    for (const gauge of Object.values(gauges)) gauge.display = gauge.target;
  }

  function stepGauges(now) {
    animationFrame = null;
    if (hud.hidden || document.hidden) {
      snapGauges();
      return;
    }
    const settled = advanceGauges(now);
    paintGauges();
    if (!settled) animationFrame = requestAnimationFrame(stepGauges);
    else animationTime = 0;
  }

  function setGaugeTargets(delta) {
    const paused = hud.hidden || document.hidden || reducedMotion.matches;
    const changed = gaugeNames.some(name => name in delta
      && clamp(number(delta[name], 0), 0, gauges[name].maximum) !== gauges[name].target);
    if (!paused && !changed) return;
    const now = performance.now();
    // Advance the old targets to packet arrival before retargeting. Restarting
    // easing on every sample would make rapidly arriving readings feel uneven.
    if (!paused && animationFrame !== null) advanceGauges(now);
    for (const name of gaugeNames) {
      if (name in delta) {
        state[name] = clamp(number(delta[name], 0), 0, gauges[name].maximum);
        gauges[name].target = state[name];
      }
    }
    if (paused) {
      snapGauges();
      if (!hud.hidden && !document.hidden) paintGauges();
      return;
    }
    if (animationFrame === null) {
      animationTime = now;
      animationFrame = requestAnimationFrame(stepGauges);
    }
  }

  function syncGaugeVisibility() {
    if (hud.hidden || document.hidden) snapGauges();
    else if (animationFrame === null) {
      snapGauges();
      paintGauges();
    }
  }

  document.addEventListener('visibilitychange', syncGaugeVisibility);
  reducedMotion.addEventListener('change', () => setGaugeTargets(state));

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
    if ('speed' in delta || 'rpm' in delta) setGaugeTargets(delta);
    if ('rpm' in delta) {
      state.rpm = clamp(number(delta.rpm, 0), 0, 100);
      hud.classList.toggle('redline', state.rpm >= 85);
    }
    if ('gear' in delta) text(refs.gear, /^[NR0-9]$|^1[0-9]$/.test(String(delta.gear)) ? String(delta.gear) : 'N');
    if ('engine' in delta || 'engineWarning' in delta) {
      refs.engine.classList.toggle('active', state.engine && !state.engineWarning);
      refs.engine.classList.toggle('damaged', state.engineWarning);
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
  }

  function configure(data) {
    if ('unit' in data) {
      const unit = data.unit === 'mph' ? 'mph' : 'kmh';
      if (unit !== config.unit) {
        // Convert the current motion too: switching units must not animate a
        // fictitious deceleration from the old numeric reading to the new one.
        if (animationFrame !== null) advanceGauges(performance.now());
        const factor = unit === 'mph' ? 2.2369362921 / 3.6 : 3.6 / 2.2369362921;
        const speed = gauges.speed;
        speed.target = clamp(speed.target * factor, 0, speed.maximum);
        speed.display = clamp(speed.display * factor, 0, speed.maximum);
        speed.velocity *= factor;
        state.speed = speed.target;
        config.unit = unit;
        if (!hud.hidden && !document.hidden) paintGauges();
      }
    }
    text(refs.unit, config.unit === 'mph' ? 'MPH' : 'KM/H');
    if ('scale' in data) style('--scale', clamp(number(data.scale, .85), .65, 1.5));
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
    render(state);
  }

  function receive(data) {
    if (!data || typeof data !== 'object') return;
    if (data.action === 'visibility') {
      hidden(hud, data.visible !== true);
      syncGaugeVisibility();
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
