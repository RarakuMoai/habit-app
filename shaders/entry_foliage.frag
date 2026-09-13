#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform float uSeconds;
uniform float uStrength;
uniform sampler2D uLeaves;
out vec4 fragColor;
void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  // The source is cropped at the left and bottom: those edges MUST stay fixed.
  float root = smoothstep(0., .22, uv.x) * smoothstep(0., .08, 1. - uv.y);
  float wave = uSeconds * 1.12 + uv.y * 3.;
  vec2 delta = root * uStrength * vec2(.012 * sin(wave), .0025 * sin(wave + .7));
  fragColor = texture(uLeaves, clamp(uv + delta, vec2(0.), vec2(1.)));
}
