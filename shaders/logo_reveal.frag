// Spec: specs/087-splash-loader-animado/spec.md
// Revela un logo "dibujándolo" por orden de trazo, con cobertura 100%.
// uOrder: R = orden de revelado (0..1), A = dentro de la silueta (1) / fuera (0).
// uLogo:  PNG del logo (premultiplicado al samplear).
#version 460 core
#include <flutter/runtime_effect.glsl>
precision mediump float;

uniform vec2 uSize;       // tamaño del área de pintado (px)
uniform float uProgress;  // 0..1 — avance del dibujado
uniform float uErase;     // 0..1 — borrado por la cola (0 = nada borrado)
uniform float uFeather;   // suavidad del borde del "lápiz"
uniform sampler2D uLogo;
uniform sampler2D uOrder;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec4 om = texture(uOrder, uv);
  vec4 c  = texture(uLogo, uv);     // premultiplicado
  float order = om.r;
  float inside = om.a;
  float drawn = smoothstep(0.0, uFeather, uProgress - order); // revelado por el dibujado
  float kept  = step(uErase, order);                          // aún no borrado
  fragColor = c * (drawn * kept * inside);
}
