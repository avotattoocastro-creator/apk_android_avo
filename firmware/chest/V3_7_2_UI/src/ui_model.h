// AVO CHEST V3.7.2 — live snapshot -> dashboard model (pure C++, host-testable).
#pragma once
#include "app_state.h"
#include "ui_dash.h"

namespace ui_model {
// Builds the seven cards ONLY from real snapshot data; stale data is never shown as OK.
void build(const AppSnapshot& s, uint32_t now_ms, dash::Model* out);
}
