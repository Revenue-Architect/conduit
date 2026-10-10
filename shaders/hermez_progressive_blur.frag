// Progressive frost for the top chrome edge: one separable Gaussian pass
// whose radius eases continuously from full (at the screen's top edge) to
// nothing, so the frost dissolves without slices or a hard line.
//
// Used through ImageFilter.shader as a BackdropFilter, composed twice
// (horizontal, then vertical). The frost sits at the top of the screen, so
// the backdrop texture's y matches the distance from that edge.
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;     // set by the engine: input texture size, physical px
uniform float uSigma;   // full-strength sigma, physical px
uniform float uFull;    // full strength down to here (physical px from top)
uniform float uEnd;     // no blur from here down
uniform vec2 uDir;      // (1, 0) horizontal pass, (0, 1) vertical pass
uniform sampler2D uTexture;

out vec4 fragColor;

const int kTaps = 12;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  float y = uv.y * uSize.y;
  float strength = 1.0 - smoothstep(uFull, uEnd, y);
  float sigma = uSigma * strength;
  vec4 base = texture(uTexture, uv);
  if (sigma < 0.35) {
    fragColor = base;
    return;
  }
  // Spread the taps over about 2.5 sigma; never closer than a pixel.
  float stepPx = max(sigma * 2.5 / float(kTaps), 1.0);
  float falloff = -0.5 / (sigma * sigma);
  vec4 sum = base;
  float weights = 1.0;
  for (int i = 1; i <= kTaps; i++) {
    float d = float(i) * stepPx;
    float w = exp(d * d * falloff);
    vec2 offset = uDir * d / uSize;
    sum += (texture(uTexture, uv + offset) + texture(uTexture, uv - offset)) * w;
    weights += 2.0 * w;
  }
  fragColor = sum / weights;
}
