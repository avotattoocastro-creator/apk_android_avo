// AVO CHEST V3.7.2 — anti-aliased software renderer for the CO5300 AMOLED (410x502).
// No LVGL. One RGB565 framebuffer in PSRAM (402 KB of 8 MB); internal RAM use is only the
// small transfer buffer used by flush(). Fonts/icons are 4-bit alpha in flash (ui_assets.h).
// Pure C++: compiled both in the firmware and in the host preview tool.
#pragma once
#include <stdint.h>
#include <stddef.h>

struct UiGlyph { uint32_t offset; uint8_t w, h; int8_t xoff, yoff; uint8_t adv; uint8_t pad; };
struct UiFont { const uint8_t* bits; const UiGlyph* glyphs; uint16_t first, last; uint8_t ascent, descent; };
struct UiIcon { const uint8_t* bits; uint16_t w, h; };

// Destination of finished pixels (Arduino_GFX on the watch, an image on the host).
struct UiPanel {
  virtual ~UiPanel() {}
  // Physical panel coordinates; x, y, w, h are always even.
  virtual void push(int16_t x, int16_t y, const uint16_t* pixels, int16_t w, int16_t h) = 0;
};

constexpr uint16_t rgb565(uint8_t r, uint8_t g, uint8_t b) {
  return (uint16_t)(((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3));
}

class UiFb {
 public:
  static constexpr int W = 410;
  static constexpr int H = 502;

  // pixels: W*H uint16 (PSRAM); line: transfer buffer of line_px pixels (internal RAM, DMA capable).
  void attach(uint16_t* pixels, uint16_t* line, size_t line_px, bool rotate180);
  bool ready() const { return px_ != nullptr; }

  void clear(uint16_t c) { fillRect(0, 0, W, H, c); }
  void fillRect(int x, int y, int w, int h, uint16_t c);
  void fillRoundRect(int x, int y, int w, int h, int r, uint16_t c);   // anti-aliased corners
  void fillCircle(float cx, float cy, float r, uint16_t c, uint8_t alpha = 255);  // anti-aliased
  void ring(float cx, float cy, float r_out, float r_in, float deg_from, float deg_to, uint16_t c, uint8_t alpha = 255);
  // Arc with rounded ends (charging ring).
  void arc(float cx, float cy, float r_out, float r_in, float deg_from, float deg_to, uint16_t c, uint8_t alpha = 255);
  void icon(const UiIcon& ic, int x, int y, uint16_t c);
  void iconCentered(const UiIcon& ic, int cx, int cy, uint16_t c) { icon(ic, cx - ic.w / 2, cy - ic.h / 2, c); }

  // UTF-8 text, baseline at y. Returns advance width.
  int text(const UiFont& f, int x, int y, const char* s, uint16_t c);
  static int textWidth(const UiFont& f, const char* s);
  int textRight(const UiFont& f, int right, int y, const char* s, uint16_t c) { return text(f, right - textWidth(f, s), y, s, c); }
  int textCenter(const UiFont& f, int cx, int y, const char* s, uint16_t c) { return text(f, cx - textWidth(f, s) / 2, y, s, c); }
  // Picks the first font of the list whose width fits max_w (last one is used anyway, clipped).
  static const UiFont& fit(const UiFont* const* fonts, int n, const char* s, int max_w);

  void markDirty(int x, int y, int w, int h);
  void markAll() { markDirty(0, 0, W, H); }
  // Sends the dirty rectangle to the panel (rotated if configured). Returns pixels sent.
  uint32_t flush(UiPanel& panel);

  uint16_t get(int x, int y) const { return px_[y * W + x]; }

 private:
  uint16_t* px_ = nullptr;
  uint16_t* line_ = nullptr;
  size_t line_px_ = 0;
  bool rot_ = true;
  int dx0_ = W, dy0_ = H, dx1_ = 0, dy1_ = 0;  // dirty rect [x0,x1) x [y0,y1)
  void blend(int x, int y, uint16_t c, uint8_t a8);  // a8: 0..255
};

// UTF-8 -> code point (Latin-1 subset is what the fonts contain). Advances *s.
uint32_t ui_utf8_next(const char** s);
