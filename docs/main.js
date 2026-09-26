import * as THREE from 'three';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';

const canvas = document.getElementById('bubbles');
const stage = canvas.parentElement;
const readout = document.getElementById('readout');
const calm = matchMedia('(prefers-reduced-motion: reduce)').matches;
const darkScheme = matchMedia('(prefers-color-scheme: dark)');

// The app's demo people, in the app's palette: Color.bubble(hue) is HSB(hue, 0.55, 0.95).
const PEOPLE = [
  { name: 'You', hue: 0.64, face: '🎧', you: true },
  { name: 'Maya', hue: 0.92 },
  { name: 'Sam', hue: 0.58, face: '😎' },
  { name: 'Ava', hue: 0.12 },
  { name: 'Leo', hue: 0.30, face: '🎸' },
  { name: 'Priya', hue: 0.72 },
  { name: 'Noah', hue: 0.06, face: '🐙' },
  { name: 'Zoe', hue: 0.45 },
];

const BUBBLE_RADIUS = 1;
const NEARBY_RADIUS = 0.26;

function bubbleColor(hue) {
  const v = 0.95, s = 0.55;
  const l = v * (1 - s / 2);
  return new THREE.Color().setHSL(hue, (v - l) / Math.min(l, 1 - l), l);
}

// Scene

const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true });
renderer.setPixelRatio(Math.min(devicePixelRatio, 2));

const scene = new THREE.Scene();
const pmrem = new THREE.PMREMGenerator(renderer);
scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
scene.environmentIntensity = 0.35;

const keyLight = new THREE.DirectionalLight(0xffffff, 1.6);
keyLight.position.set(-2, 3, 4);
scene.add(keyLight);

const camera = new THREE.PerspectiveCamera(32, 1, 0.1, 100);
let cameraDistance = 8;

// Your bubble: a thin film with iridescent edges that wobbles when someone passes through it.

const bubbleUniforms = {
  uTime: { value: 0 },
  uWobble: { value: 0 },
  uImpact: { value: new THREE.Vector3(0, 1, 0) },
  uDark: { value: darkScheme.matches ? 1 : 0 },
};

const bubble = new THREE.Mesh(
  new THREE.SphereGeometry(BUBBLE_RADIUS, 128, 96),
  new THREE.ShaderMaterial({
    uniforms: bubbleUniforms,
    transparent: true,
    depthWrite: false,
    side: THREE.DoubleSide,
    vertexShader: /* glsl */ `
      uniform float uTime;
      uniform float uWobble;
      uniform vec3 uImpact;
      varying vec3 vNormal;
      varying vec3 vWorld;
      void main() {
        vec3 n = normalize(normal);
        float d = dot(n, uImpact);
        float wobble = uWobble * sin(d * 4.5 - uTime * 16.0) * (0.55 + 0.45 * d);
        float breathe = 0.012 * sin(uTime * 1.3 + n.y * 3.0) + 0.01 * sin(uTime * 1.7 + n.x * 4.0);
        vec4 world = modelMatrix * vec4(position + n * (wobble + breathe), 1.0);
        vWorld = world.xyz;
        vNormal = normalize(mat3(modelMatrix) * n);
        gl_Position = projectionMatrix * viewMatrix * world;
      }
    `,
    fragmentShader: /* glsl */ `
      uniform float uTime;
      uniform float uDark;
      varying vec3 vNormal;
      varying vec3 vWorld;
      vec3 film(float t) {
        return 0.5 + 0.5 * cos(6.28318 * (t + vec3(0.0, 0.33, 0.67)));
      }
      void main() {
        vec3 v = normalize(cameraPosition - vWorld);
        vec3 n = normalize(vNormal);
        if (!gl_FrontFacing) n = -n;
        float edge = 1.0 - abs(dot(n, v));
        float fresnel = pow(edge, 2.4);
        float t = edge * 1.3 + 0.12 * sin(vWorld.y * 3.0 + uTime * 0.5) + 0.08 * vWorld.x + uTime * 0.04;
        vec3 color = mix(film(t), vec3(1.0), mix(0.15, 0.35, uDark));
        vec3 l1 = normalize(vec3(-0.5, 0.8, 0.6));
        vec3 l2 = normalize(vec3(0.7, -0.4, 0.4));
        float spec = pow(max(dot(reflect(-l1, n), v), 0.0), 80.0)
                   + 0.5 * pow(max(dot(reflect(-l2, n), v), 0.0), 40.0);
        float alpha = mix(0.04, 0.03, uDark) + fresnel * mix(0.7, 0.8, uDark);
        if (!gl_FrontFacing) alpha *= 0.5;
        gl_FragColor = vec4(color + spec, clamp(alpha + spec, 0.0, 1.0));
      }
    `,
  }),
);
bubble.renderOrder = 3;
scene.add(bubble);

darkScheme.addEventListener('change', (e) => { bubbleUniforms.uDark.value = e.matches ? 1 : 0; });

// People: glossy bubbles with a face (an emoji or their initial) and a glow for when they talk.

function spriteTexture(draw) {
  const c = document.createElement('canvas');
  c.width = c.height = 256;
  draw(c.getContext('2d'));
  const texture = new THREE.CanvasTexture(c);
  texture.colorSpace = THREE.SRGBColorSpace;
  texture.userData.redraw = () => {
    c.getContext('2d').clearRect(0, 0, 256, 256);
    draw(c.getContext('2d'));
    texture.needsUpdate = true;
  };
  return texture;
}

const glowTexture = spriteTexture((ctx) => {
  const g = ctx.createRadialGradient(128, 128, 0, 128, 128, 128);
  g.addColorStop(0, 'rgba(255,255,255,1)');
  g.addColorStop(0.35, 'rgba(255,255,255,0.7)');
  g.addColorStop(1, 'rgba(255,255,255,0)');
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, 256, 256);
});

function faceTexture(person) {
  return spriteTexture((ctx) => {
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    if (person.face) {
      ctx.font = '112px "Apple Color Emoji", "Segoe UI Emoji", "Noto Color Emoji", sans-serif';
      ctx.fillText(person.face, 128, 136);
    } else {
      ctx.font = '600 104px ui-rounded, "SF Pro Rounded", Nunito, system-ui, sans-serif';
      ctx.fillStyle = 'rgba(30, 24, 40, 0.62)';
      ctx.fillText(person.name[0], 128, 134);
    }
  });
}

const sphereGeometry = new THREE.SphereGeometry(1, 64, 48);

const people = PEOPLE.map((def, i) => {
  const color = bubbleColor(def.hue);
  const mesh = new THREE.Mesh(sphereGeometry, new THREE.MeshPhysicalMaterial({
    color,
    roughness: 0.35,
    clearcoat: 1,
    clearcoatRoughness: 0.08,
    emissive: color,
    emissiveIntensity: 0.15,
  }));
  const face = new THREE.Sprite(new THREE.SpriteMaterial({ map: faceTexture(def), depthTest: false, depthWrite: false }));
  face.renderOrder = 2;
  const halo = new THREE.Sprite(new THREE.SpriteMaterial({
    map: glowTexture, color, transparent: true, opacity: 0, depthWrite: false,
  }));
  halo.renderOrder = 1;
  scene.add(mesh, face, halo);

  const person = {
    ...def, index: i, color, mesh, face, halo,
    inside: !!def.you,
    wasInside: !!def.you,
    pos: new THREE.Vector3(), vel: new THREE.Vector3(),
    anchor: new THREE.Vector3(), target: new THREE.Vector3(),
    radius: def.you ? 0.3 : NEARBY_RADIUS,
    phase: i * 2.39,
    scale: 0, scaleVel: 0, appearAt: 0.15 + i * 0.07,
    level: 0,
  };
  mesh.userData.person = person;
  return person;
});

const you = people[0];
const members = [you];

// Layout: nearby people float on an ellipse around your bubble; members form a ring inside it.

function layout() {
  const w = stage.clientWidth, h = stage.clientHeight;
  if (!w || !h) return;
  renderer.setSize(w, h, false);
  camera.aspect = w / h;
  camera.updateProjectionMatrix();

  // Fit this much of the world around the center into the short side.
  const need = 2.15;
  const halfH = camera.aspect < 1 ? need / camera.aspect : need;
  const halfW = halfH * camera.aspect;
  cameraDistance = halfH / Math.tan(THREE.MathUtils.degToRad(camera.fov / 2));

  const ax = Math.min(halfW * 0.8, 3.6);
  const ay = Math.min(halfH * 0.8, 3.0);
  const nearby = people.filter((p) => !p.you);
  nearby.forEach((p, i) => {
    const angle = -Math.PI / 2 + ((i + 0.5) / nearby.length) * Math.PI * 2 + Math.sin(p.phase) * 0.18;
    const a = new THREE.Vector2(Math.cos(angle) * ax, Math.sin(angle) * ay);
    if (a.length() < 1.6) a.setLength(1.6);
    p.anchor.set(a.x, a.y, Math.sin(p.phase * 1.7) * 0.35);
  });
}

function memberSlot(k, n) {
  if (n === 1) return { pos: new THREE.Vector3(), radius: 0.3 };
  const ring = n === 2 ? 0.42 : n <= 4 ? 0.5 : 0.56;
  const radius = n <= 4 ? 0.27 : n <= 6 ? 0.24 : 0.21;
  const angle = Math.PI / 2 - (k / n) * Math.PI * 2;
  return { pos: new THREE.Vector3(Math.cos(angle) * ring, Math.sin(angle) * ring, 0), radius };
}

new ResizeObserver(layout).observe(stage);
layout();

// Sound: a little synthesized bloop, pitched per person.

let audio;
function bloop(from, to, duration = 0.15, volume = 0.2) {
  try {
    audio ??= new (window.AudioContext || window.webkitAudioContext)();
    if (audio.state === 'suspended') audio.resume();
    const t = audio.currentTime;
    const osc = audio.createOscillator();
    const gain = audio.createGain();
    osc.type = 'sine';
    osc.frequency.setValueAtTime(from, t);
    osc.frequency.exponentialRampToValueAtTime(to, t + duration);
    gain.gain.setValueAtTime(0.0001, t);
    gain.gain.exponentialRampToValueAtTime(volume, t + 0.012);
    gain.gain.exponentialRampToValueAtTime(0.0001, t + duration + 0.08);
    osc.connect(gain).connect(audio.destination);
    osc.start(t);
    osc.stop(t + duration + 0.1);
  } catch { /* no audio, no problem */ }
}

const pitch = (p) => 300 * Math.pow(2, (p.index * 3) / 12);

// Joining and leaving

function wobble(direction, amount) {
  bubbleUniforms.uImpact.value.copy(direction).normalize();
  bubbleUniforms.uWobble.value = Math.max(bubbleUniforms.uWobble.value, amount * (calm ? 0.3 : 1));
}

function tapPerson(p) {
  p.scaleVel += 6;
  if (p.you) {
    bloop(pitch(p) * 0.8, pitch(p) * 1.2, 0.1, 0.16);
    wobble(p.pos.clone().add(new THREE.Vector3(0, 0.01, 0)), 0.03);
  } else if (p.inside) {
    members.splice(members.indexOf(p), 1);
    p.inside = false;
    bloop(pitch(p) * 1.5, pitch(p) * 0.55, 0.16);
  } else {
    members.push(p);
    p.inside = true;
    bloop(pitch(p) * 0.6, pitch(p) * 1.6, 0.13);
  }
  updateReadout();
}

function pokeBubble(point) {
  wobble(point, 0.05);
  bloop(170, 280, 0.2, 0.22);
}

function updateReadout() {
  const names = members.filter((p) => !p.you).map((p) => p.name);
  let text;
  if (names.length === 0) text = 'Just you so far. Tap someone to invite them.';
  else if (names.length === PEOPLE.length - 1) text = 'Everyone’s in. You can all hear each other.';
  else if (names.length >= 4) text = `You and ${names.length} friends can hear each other.`;
  else if (names.length === 1) text = `You and ${names[0]} can hear each other.`;
  else text = `You, ${names.slice(0, -1).join(', ')} and ${names.at(-1)} can hear each other.`;
  readout.textContent = text;
}

// Pointer: tap to invite or remove; hover highlights; the camera leans a little toward the pointer.

const raycaster = new THREE.Raycaster();
const pointer = new THREE.Vector2(9, 9);
const lean = new THREE.Vector2();
let hovered = null;
let down = null;

function setPointer(e) {
  const rect = canvas.getBoundingClientRect();
  pointer.set(((e.clientX - rect.left) / rect.width) * 2 - 1, -((e.clientY - rect.top) / rect.height) * 2 + 1);
}

function hit() {
  raycaster.setFromCamera(pointer, camera);
  const person = raycaster.intersectObjects(people.map((p) => p.mesh), false)[0];
  if (person) return { person: person.object.userData.person };
  const shell = raycaster.intersectObject(bubble, false)[0];
  if (shell) return { point: shell.point };
  return null;
}

canvas.addEventListener('pointermove', (e) => {
  setPointer(e);
  if (e.pointerType === 'mouse') lean.copy(pointer);
});
canvas.addEventListener('pointerleave', () => { pointer.set(9, 9); lean.set(0, 0); });
canvas.addEventListener('pointerdown', (e) => {
  setPointer(e);
  down = { x: e.clientX, y: e.clientY };
});
canvas.addEventListener('pointerup', (e) => {
  if (!down || Math.hypot(e.clientX - down.x, e.clientY - down.y) > 10) return;
  down = null;
  setPointer(e);
  const h = hit();
  if (h?.person) tapPerson(h.person);
  else if (h?.point) pokeBubble(h.point);
  if (e.pointerType !== 'mouse') pointer.set(9, 9);
});
canvas.addEventListener('keydown', (e) => {
  if (e.key !== 'Enter' && e.key !== ' ') return;
  e.preventDefault();
  const next = people.find((p) => !p.inside) ?? members.at(-1);
  if (next && !next.you) tapPerson(next);
});

// Conversation: people in the bubble take turns talking, and glow with their voice.

let speaker = null;
let nextTurn = 0;

function converse(t) {
  if (members.length < 2) {
    speaker = null;
    return;
  }
  if (t > nextTurn || (speaker && !speaker.inside)) {
    const choices = members.filter((p) => p !== speaker);
    speaker = Math.random() < 0.15 ? null : choices[Math.floor(Math.random() * choices.length)];
    nextTurn = t + 1.1 + Math.random() * 1.8;
  }
}

// Animation

const timer = new THREE.Timer();
timer.connect(document);
const toCamera = new THREE.Vector3();
const force = new THREE.Vector3();

function frame(time) {
  timer.update(time);
  const dt = Math.min(timer.getDelta(), 1 / 30);
  const t = timer.getElapsed();
  const bob = calm ? 0.2 : 1;

  camera.position.x += (lean.x * 0.35 - camera.position.x) * Math.min(1, dt * 3);
  camera.position.y += (lean.y * 0.25 - camera.position.y) * Math.min(1, dt * 3);
  camera.position.z = cameraDistance;
  camera.lookAt(0, 0, 0);

  bubbleUniforms.uTime.value = t;
  bubbleUniforms.uWobble.value *= Math.exp(-dt * 3.2);

  const h = hit();
  hovered = h?.person ?? null;
  canvas.style.cursor = h ? 'pointer' : 'default';

  converse(t);

  people.forEach((p) => {
    // Where this person wants to be.
    let radius = NEARBY_RADIUS;
    if (p.inside) {
      const slot = memberSlot(members.indexOf(p), members.length);
      p.target.copy(slot.pos);
      p.target.x += Math.sin(t * 0.9 + p.phase) * 0.015 * bob;
      p.target.y += Math.cos(t * 0.8 + p.phase) * 0.02 * bob;
      radius = slot.radius;
    } else {
      p.target.copy(p.anchor);
      p.target.x += Math.sin(t * 0.55 + p.phase) * 0.09 * bob;
      p.target.y += Math.cos(t * 0.5 + p.phase * 1.3) * 0.11 * bob;
      p.target.z += Math.sin(t * 0.4 + p.phase) * 0.15 * bob;
    }
    p.radius += (radius - p.radius) * Math.min(1, dt * 6);

    // A slightly bouncy spring toward it.
    force.subVectors(p.target, p.pos).multiplyScalar(55).addScaledVector(p.vel, -10);
    p.vel.addScaledVector(force, dt);
    p.pos.addScaledVector(p.vel, dt);

    // Wobble your bubble when someone passes through its skin.
    const isInside = p.pos.length() < BUBBLE_RADIUS;
    if (isInside !== p.wasInside) {
      wobble(p.pos, 0.07);
      p.wasInside = isInside;
    }

    // Pop in at the start, grow on hover, bounce on tap.
    const scaleTarget = t < p.appearAt ? 0 : hovered === p ? 1.1 : 1;
    p.scaleVel += ((scaleTarget - p.scale) * 180 - p.scaleVel * 14) * dt;
    p.scale += p.scaleVel * dt;

    // Talking.
    const voice = p === speaker ? 0.55 + 0.45 * Math.sin(t * 9 + p.phase) * Math.sin(t * 2.3 + p.phase * 2) : 0;
    p.level += (voice - p.level) * Math.min(1, dt * 10);

    const size = p.radius * Math.max(0, p.scale) * (1 + p.level * 0.07);
    p.mesh.position.copy(p.pos);
    p.mesh.scale.setScalar(size);
    p.mesh.material.emissiveIntensity = 0.15 + p.level * 0.3;

    toCamera.subVectors(camera.position, p.pos).normalize();
    p.face.position.copy(p.pos).addScaledVector(toCamera, size * 1.02);
    p.face.scale.setScalar(size * 2);

    p.halo.position.copy(p.pos);
    p.halo.scale.setScalar(size * 4);
    p.halo.material.opacity = p.level;
  });

  renderer.render(scene, camera);
}

document.fonts?.ready.then(() => people.forEach((p) => p.face.material.map.userData.redraw()));
people.forEach((p) => p.pos.copy(p.inside ? new THREE.Vector3() : p.anchor));
renderer.setAnimationLoop(frame);
