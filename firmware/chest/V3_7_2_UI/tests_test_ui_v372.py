# Static checks for the V3.7.2 anti-aliased UI (copied into tests/ by the workflow).
from pathlib import Path
src = Path(__file__).resolve().parents[1] / "AVO_CHEST_V3_5_0" / "src"
ui = (src / "ui.cpp").read_text()
model = (src / "ui_model.cpp").read_text()
dash = (src / "ui_dash.cpp").read_text()
fb = (src / "ui_fb.cpp").read_text()
assert "UI_ROTATE_180 = true" in ui, "180-degree software rotation must be on"
assert "gfx->setRotation(0)" in ui, "controller orientation (and its 22 px column offset) unchanged"
assert "MALLOC_CAP_SPIRAM" in ui and "UiFb::W * UiFb::H * 2" in ui, "framebuffer must live in PSRAM"
assert "lvgl.h" not in (ui + dash + fb + model).lower() and "lv_" not in (ui + dash + fb + model), "no LVGL"
assert "const_cast<uint16_t*>" in ui, "fast (non-PROGMEM) bitmap path"
assert "& ~1" in fb, "CO5300 even alignment in flush"
for k in ("last_batch_ms[k], 3000", "fresh(s.link.last_rx_ms, 2000)", "fresh(s.gnss.rx_ms, 3000)", "s.rtcm.flowing"):
    assert k in model, k
assert "draw_rec_dot" in ui and "500" in ui, "only the SD dot blinks"
for t in ("BLUETOOTH", "CHALECO", "ESPALDA", "CINCHA (IMU)", "GPS / RTK", "TARJETA SD", "BATERÍA"):
    assert t in dash, t
for name, text in (("ui", ui), ("model", model), ("dash", dash), ("fb", fb)):
    assert text.count("{") == text.count("}"), name
print("PASS: V3.7.2 UI static checks (host preview runs separately; not a hardware test)")
