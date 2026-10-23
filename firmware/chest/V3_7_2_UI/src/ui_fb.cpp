// AVO CHEST V3.7.2 — see ui_fb.h.
#include "ui_fb.h"
#include <math.h>
#include <string.h>

static inline int imin(int a, int b) { return a < b ? a : b; }
static inline int imax(int a, int b) { return a > b ? a : b; }

void UiFb::attach(uint16_t* pixels, uint16_t* line, size_t line_px, bool rotate180) {
  px_ = pixels; line_ = line; line_px_ = line_px; rot_ = rotate180;
  dx0_ = W; dy0_ = H; dx1_ = 0; dy1_ = 0;
}

void UiFb::markDirty(int x, int y, int w, int h) {
  if (w <= 0 || h <= 0) return;
  dx0_ = imin(dx0_, imax(0, x)); dy0_ = imin(dy0_, imax(0, y));
  dx1_ = imax(dx1_, imin(W, x + w)); dy1_ = imax(dy1_, imin(H, y + h));
}

void UiFb::blend(int x, int y, uint16_t c, uint8_t a) {
  if ((unsigned)x >= (unsigned)W || (unsigned)y >= (unsigned)H || a == 0) return;
  uint16_t* p = &px_[y * W + x];
  if (a >= 250) { *p = c; return; }
  const uint16_t d = *p;
  const uint32_t ia = 255 - a;
  const uint32_t r = (((c >> 11) & 31) * a + ((d >> 11) & 31) * ia + 127) / 255;
  const uint32_t g = (((c >> 5) & 63) * a + ((d >> 5) & 63) * ia + 127) / 255;
  const uint32_t b = ((c & 31) * a + (d & 31) * ia + 127) / 255;
  *p = (uint16_t)((r << 11) | (g << 5) | b);
}

void UiFb::fillRect(int x, int y, int w, int h, uint16_t c) {
  const int x0 = imax(0, x), y0 = imax(0, y), x1 = imin(W, x + w), y1 = imin(H, y + h);
  if (x0 >= x1 || y0 >= y1) return;
  for (int yy = y0; yy < y1; ++yy) {
    uint16_t* p = &px_[yy * W + x0];
    for (int xx = x0; xx < x1; ++xx) *p++ = c;
  }
  markDirty(x0, y0, x1 - x0, y1 - y0);
}

static uint8_t coverage(float dist, float r) {
  // dist from circle centre (pixel centre); 1-pixel linear edge.
  const float v = r + 0.5f - dist;
  if (v <= 0) return 0;
  if (v >= 1) return 255;
  return (uint8_t)(v * 255.0f + 0.5f);
}

void UiFb::fillRoundRect(int x, int y, int w, int h, int r, uint16_t c) {
  if (w <= 0 || h <= 0) return;
  r = imin(r, imin(w, h) / 2);
  if (r <= 0) { fillRect(x, y, w, h, c); return; }
  fillRect(x + r, y, w - 2 * r, h, c);
  fillRect(x, y + r, r, h - 2 * r, c);
  fillRect(x + w - r, y + r, r, h - 2 * r, c);
  // Four anti-aliased corners: circle centres on pixel edges, coverage from pixel centres.
  const float cx[2] = {(float)(x + r), (float)(x + w - r)};
  const float cy[2] = {(float)(y + r), (float)(y + h - r)};
  for (int corner = 0; corner < 4; ++corner) {
    const int sx = (corner & 1) ? x + w - r : x;
    const int sy = (corner & 2) ? y + h - r : y;
    const float ccx = cx[corner & 1], ccy = cy[(corner >> 1) & 1];
    for (int j = 0; j < r; ++j)
      for (int i = 0; i < r; ++i) {
        const float dx = sx + i + 0.5f - ccx, dy = sy + j + 0.5f - ccy;
        blend(sx + i, sy + j, c, coverage(sqrtf(dx * dx + dy * dy), (float)r - 0.5f));
      }
  }
  markDirty(x, y, w, h);
}

void UiFb::maskOutsideRoundRect(int rx, int ry, int rw, int rh, int r, int x, int y, int w, int h, uint16_t outside) {
  const int x0 = imax(0, x), y0 = imax(0, y), x1 = imin(W, x + w), y1 = imin(H, y + h);
  for (int yy = y0; yy < y1; ++yy)
    for (int xx = x0; xx < x1; ++xx) {
      const float px = xx + 0.5f, py = yy + 0.5f;
      if (px < rx || py < ry || px > rx + rw || py > ry + rh) { blend(xx, yy, outside, 255); continue; }
      // Only the four corner squares are curved.
      const float ccx = px < rx + r ? (float)(rx + r) : px > rx + rw - r ? (float)(rx + rw - r) : px;
      const float ccy = py < ry + r ? (float)(ry + r) : py > ry + rh - r ? (float)(ry + rh - r) : py;
      if (ccx == px || ccy == py) continue;
      const float dx = px - ccx, dy = py - ccy;
      const uint8_t inside = coverage(sqrtf(dx * dx + dy * dy), (float)r - 0.5f);
      if (inside < 255) blend(xx, yy, outside, (uint8_t)(255 - inside));
    }
  markDirty(x0, y0, x1 - x0, y1 - y0);
}

void UiFb::fillCircle(float cx, float cy, float r, uint16_t c, uint8_t alpha) {
  const int x0 = (int)floorf(cx - r - 1), x1 = (int)ceilf(cx + r + 1);
  const int y0 = (int)floorf(cy - r - 1), y1 = (int)ceilf(cy + r + 1);
  for (int y = y0; y <= y1; ++y)
    for (int x = x0; x <= x1; ++x) {
      const float dx = x + 0.5f - cx, dy = y + 0.5f - cy;
      blend(x, y, c, (uint8_t)(coverage(sqrtf(dx * dx + dy * dy), r) * alpha / 255));
    }
  markDirty(x0, y0, x1 - x0 + 1, y1 - y0 + 1);
}

void UiFb::arc(float cx, float cy, float ro, float ri, float a0, float a1, uint16_t c, uint8_t alpha) {
  if (a1 <= a0) return;
  ring(cx, cy, ro, ri, a0, a1, c, alpha);
  if (a1 - a0 >= 360.0f) return;
  const float rm = (ro + ri) / 2, rc = (ro - ri) / 2;
  const float ends[2] = {a0, a1};
  for (float a : ends) {
    const float rad = a * 0.0174532925f;
    fillCircle(cx + rm * sinf(rad), cy - rm * cosf(rad), rc, c, alpha);
  }
}

void UiFb::ring(float cx, float cy, float ro, float ri, float a0, float a1, uint16_t c, uint8_t alpha) {
  // Angles in degrees, 0 = 12 o'clock, clockwise.
  if (a1 <= a0) return;
  const int x0 = (int)floorf(cx - ro - 1), x1 = (int)ceilf(cx + ro + 1);
  const int y0 = (int)floorf(cy - ro - 1), y1 = (int)ceilf(cy + ro + 1);
  const bool full = a1 - a0 >= 360.0f;
  for (int y = y0; y <= y1; ++y)
    for (int x = x0; x <= x1; ++x) {
      const float dx = x + 0.5f - cx, dy = y + 0.5f - cy;
      const float d = sqrtf(dx * dx + dy * dy);
      if (d > ro + 1 || d < ri - 1) continue;
      if (!full) {
        float ang = atan2f(dx, -dy) * 57.2957795f;
        if (ang < 0) ang += 360.0f;
        if (ang < a0 || ang > a1) continue;
      }
      const uint8_t outer = coverage(d, ro);
      const uint8_t inner = 255 - coverage(d, ri);
      blend(x, y, c, (uint8_t)((outer < inner ? outer : inner) * alpha / 255));
    }
  markDirty(x0, y0, x1 - x0 + 1, y1 - y0 + 1);
}

void UiFb::icon(const UiIcon& ic, int x, int y, uint16_t c) {
  const int stride = (ic.w + 1) / 2;
  for (int j = 0; j < ic.h; ++j)
    for (int i = 0; i < ic.w; ++i) {
      const uint8_t b = ic.bits[j * stride + i / 2];
      const uint8_t a4 = (i & 1) ? (b & 15) : (b >> 4);
      if (a4) blend(x + i, y + j, c, (uint8_t)(a4 * 17));
    }
  markDirty(x, y, ic.w, ic.h);
}

uint32_t ui_utf8_next(const char** s) {
  const uint8_t* p = (const uint8_t*)*s;
  uint32_t c = *p++;
  if (c >= 0x80) {
    int extra = (c >= 0xF0) ? 3 : (c >= 0xE0) ? 2 : (c >= 0xC0) ? 1 : 0;
    c &= (extra == 3) ? 0x07 : (extra == 2) ? 0x0F : 0x1F;
    while (extra-- > 0 && (*p & 0xC0) == 0x80) c = (c << 6) | (*p++ & 0x3F);
  }
  *s = (const char*)p;
  return c;
}

static const UiGlyph* glyph_of(const UiFont& f, uint32_t cp) {
  if (cp < f.first || cp > f.last) cp = '?';
  if (cp < f.first || cp > f.last) return nullptr;
  const UiGlyph* g = &f.glyphs[cp - f.first];
  if (g->adv == 0 && cp != '?') return glyph_of(f, '?');
  return g;
}

int UiFb::textWidth(const UiFont& f, const char* s) {
  int w = 0;
  while (s && *s) { const UiGlyph* g = glyph_of(f, ui_utf8_next(&s)); if (g) w += g->adv; }
  return w;
}

const UiFont& UiFb::fit(const UiFont* const* fonts, int n, const char* s, int max_w) {
  for (int i = 0; i < n; ++i) if (textWidth(*fonts[i], s) <= max_w) return *fonts[i];
  return *fonts[n - 1];
}

int UiFb::text(const UiFont& f, int x, int y, const char* s, uint16_t c) {
  const int start = x;
  while (s && *s) {
    const UiGlyph* g = glyph_of(f, ui_utf8_next(&s));
    if (!g) continue;
    if (g->w && g->h) {
      const uint8_t* bits = f.bits + g->offset;
      const int stride = (g->w + 1) / 2;
      const int gx = x + g->xoff, gy = y + g->yoff;
      for (int j = 0; j < g->h; ++j)
        for (int i = 0; i < g->w; ++i) {
          const uint8_t b = bits[j * stride + i / 2];
          const uint8_t a4 = (i & 1) ? (b & 15) : (b >> 4);
          if (a4) blend(gx + i, gy + j, c, (uint8_t)(a4 * 17));
        }
      markDirty(gx, gy, g->w, g->h);
    }
    x += g->adv;
  }
  return x - start;
}

uint32_t UiFb::flush(UiPanel& panel) {
  if (dx0_ >= dx1_ || dy0_ >= dy1_) return 0;
  // CO5300 needs even column/row start and even size: widen to even bounds (W, H are even).
  int x0 = dx0_ & ~1, y0 = dy0_ & ~1, x1 = (dx1_ + 1) & ~1, y1 = (dy1_ + 1) & ~1;
  if (x1 > W) x1 = W;
  if (y1 > H) y1 = H;
  dx0_ = W; dy0_ = H; dx1_ = 0; dy1_ = 0;
  const int w = x1 - x0;
  int rows = (int)(line_px_ / (size_t)w);
  if (rows < 2) rows = 2;               // line buffer is sized for at least 2 full rows
  rows &= ~1;
  uint32_t sent = 0;
  if (!rot_) {
    for (int y = y0; y < y1; y += rows) {
      const int n = imin(rows, y1 - y);
      for (int j = 0; j < n; ++j) memcpy(&line_[j * w], &px_[(y + j) * W + x0], (size_t)w * 2);
      panel.push((int16_t)x0, (int16_t)y, line_, (int16_t)w, (int16_t)n);
      sent += (uint32_t)w * n;
    }
    return sent;
  }
  // 180°: physical (W-1-x, H-1-y). Physical rect = [W-x1, W-x0) x [H-y1, H-y0), still even.
  const int px0 = W - x1;
  for (int py = H - y1; py < H - y0; py += rows) {
    const int n = imin(rows, (H - y0) - py);
    for (int j = 0; j < n; ++j) {
      const uint16_t* src = &px_[(H - 1 - (py + j)) * W + (x1 - 1)];
      uint16_t* dst = &line_[j * w];
      for (int i = 0; i < w; ++i) dst[i] = *(src - i);
    }
    panel.push((int16_t)px0, (int16_t)py, line_, (int16_t)w, (int16_t)n);
    sent += (uint32_t)w * n;
  }
  return sent;
}
