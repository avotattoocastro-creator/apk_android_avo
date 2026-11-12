#!/usr/bin/env python3
"""AVO CHEST 3.7.8 VINCULAR — applied on top of 3.7.7 DESPERTAR (run from the tree root).

User request (09/11/2026): three quick presses of the BOOT/USER button put the watch in "connect a phone" mode.
  * BootButton: new TRIPLE event (3 clicks, each within 350 ms of the previous one). A double click is now reported
    350 ms after the second release (it waits to see whether a third click comes).
  * Triple click → ble::pair_mode(120 s):
      - the phone connected now (if any) is disconnected and blocked during the window, so its automatic reconnection
        does not take the watch back while the new phone connects (the watch accepts one phone at a time);
      - advertising is restarted;
      - the authorization request (CLAIM) of the new phone is confirmed automatically: the triple click already was
        the physical confirmation, there is no need to press BOOT again within 60 s;
      - the window ends after 120 s, or when a phone has been authorized, or with another triple click.
  * Screen: the Bluetooth card shows "MODO VINCULAR" while the window is open.
Nothing else changes.
"""
from pathlib import Path
import sys

SRC = Path('AVO_CHEST_V3_5_0') / 'src'
LIB = Path('lib') / 'avo_core' / 'src'


def patch(path: Path, old: str, new: str, count: int = 1):
    s = path.read_text()
    n = s.count(old)
    if n != count:
        sys.exit(f'apply_v378: {path}: expected {count} match(es), found {n}:\n{old}')
    path.write_text(s.replace(old, new))


# ---------------------------------------------------------------- BootButton TRIPLE
patch(LIB / 'avo_input.h', '  enum Event { NONE = 0, SHORT, DOUBLE, LONG };',
      '  enum Event { NONE = 0, SHORT, DOUBLE, LONG, TRIPLE };   // V3.7.8: TRIPLE')
patch(LIB / 'avo_input.cpp',
      '        clicks_++;\n'
      '        if (clicks_ >= 2) { clicks_ = 0; ev = DOUBLE; }\n',
      '        clicks_++;\n'
      '        if (clicks_ >= 3) { clicks_ = 0; ev = TRIPLE; }   // V3.7.8: DOUBLE waits for a possible third click\n')
patch(LIB / 'avo_input.cpp',
      '  if (!stable_ && clicks_ == 1 && now - release_t_ >= dbl_) { clicks_ = 0; ev = SHORT; }\n',
      '  if (!stable_ && clicks_ >= 1 && now - release_t_ >= dbl_) { ev = clicks_ == 1 ? SHORT : DOUBLE; clicks_ = 0; }\n')

# ---------------------------------------------------------------- state + services
patch(SRC / 'app_state.h', '  bool claim_pending = false;\n  uint8_t auth_keys = 0;\n',
      '  bool claim_pending = false;\n  bool pair_mode = false;          // V3.7.8: "connect a phone" window (3 BOOT clicks)\n  uint8_t auth_keys = 0;\n')
patch(SRC / 'services.h', 'bool claim_confirm();\nvoid tick();',
      'bool claim_confirm();\n'
      '// V3.7.8: "connect a phone" window: drops and blocks the current phone, advertises, auto-confirms the next CLAIM.\n'
      '// on == false closes it. Returns the new state.\n'
      'bool pair_mode(bool on, uint32_t window_ms = 120000);\n'
      'bool pair_mode_active();\n'
      'void tick();')

# ---------------------------------------------------------------- BLE
BLE = SRC / 'ble_service.cpp'
patch(BLE,
      'bool claim_confirm() {\n'
      '  if (!s_auth) return false;\n'
      '  auth_lock();\n'
      '  bool r = s_auth->claim_confirm(sys::ms());\n'
      '  auth_publish();\n'
      '  auth_unlock();\n'
      '  return r;\n'
      '}\n',
      'bool claim_confirm() {\n'
      '  if (!s_auth) return false;\n'
      '  auth_lock();\n'
      '  bool r = s_auth->claim_confirm(sys::ms());\n'
      '  auth_publish();\n'
      '  auth_unlock();\n'
      '  return r;\n'
      '}\n'
      '\n'
      '// ------------------------------------------------------------------ V3.7.8 "connect a phone" window\n'
      'static volatile uint32_t s_pm_until = 0;          // 0 = closed\n'
      'static NimBLEAddress s_pm_block;                   // phone dropped when the window opened (blocked during it)\n'
      'static volatile bool s_pm_block_set = false;\n'
      'static void pm_publish() { bool a = s_pm_until != 0; appstate::update([&](AppSnapshot& x) { x.ble.pair_mode = a; }); }\n'
      'bool pair_mode_active() {\n'
      '  if (s_pm_until && (int32_t)(sys::ms() - s_pm_until) >= 0) { s_pm_until = 0; s_pm_block_set = false; pm_publish(); Serial.println("[AVO BLE] modo vincular: fin (tiempo)"); }\n'
      '  return s_pm_until != 0;\n'
      '}\n'
      'bool pair_mode(bool on, uint32_t window_ms) {\n'
      '  if (!on) { s_pm_until = 0; s_pm_block_set = false; pm_publish(); Serial.println("[AVO BLE] modo vincular: cerrado"); return false; }\n'
      '  s_pm_until = (sys::ms() + window_ms) | 1u;\n'
      '  s_pm_block_set = false;\n'
      '  if (s_srv && s_connected && s_conn != 0xFFFF) {\n'
      '    NimBLEConnInfo ci = s_srv->getPeerInfoByHandle(s_conn);\n'
      '    s_pm_block = ci.getIdAddress();\n'
      '    s_pm_block_set = true;\n'
      '    Serial.printf("[AVO BLE] modo vincular: desconecto el telefono actual %s (bloqueado %u s)\\n", s_pm_block.toString().c_str(), (unsigned)(window_ms / 1000));\n'
      '    s_srv->disconnect(s_conn);\n'
      '  }\n'
      '  NimBLEDevice::startAdvertising();\n'
      '  pm_publish();\n'
      '  bb::log(BbCode::BLE_CONNECT, 0, 0x7A1D, window_ms / 1000, "pair mode (3 clicks)");\n'
      '  Serial.printf("[AVO BLE] modo vincular %u s: el proximo telefono se autoriza sin pulsar BOOT\\n", (unsigned)(window_ms / 1000));\n'
      '  return true;\n'
      '}\n')
# CLAIM auto-confirm inside the window
patch(BLE,
      '      bool ok = s_auth->claim_begin(sys::ms(), r.ok() ? name : "");\n'
      '      auth_publish();\n'
      '      auth_unlock();\n'
      '      ui::wake();\n',
      '      bool ok = s_auth->claim_begin(sys::ms(), r.ok() ? name : "");\n'
      '      auth_publish();\n'
      '      auth_unlock();\n'
      '      ui::wake();\n'
      '      if (ok && pair_mode_active() && claim_confirm()) {   // V3.7.8: the 3 clicks were the physical confirmation\n'
      '        bb::log(BbCode::BLE_CONNECT, 0, 0xC1A2, 0, "phone authorized (pair mode)");\n'
      '        Serial.println("[AVO BLE] modo vincular: telefono autorizado sin BOOT");\n'
      '      }\n')
# window closes once the key was delivered
patch(BLE,
      '      if (cr == AuthManager::CLAIM_DONE) {\n',
      '      if (cr == AuthManager::CLAIM_DONE) {\n'
      '        if (s_pm_until) pair_mode(false);   // V3.7.8: the new phone is authorized\n')
# block the dropped phone while the window is open
patch(BLE,
      '  void onConnect(NimBLEServer* server, NimBLEConnInfo& info) override {\n'
      '    (void)server;\n',
      '  void onConnect(NimBLEServer* server, NimBLEConnInfo& info) override {\n'
      '    if (s_pm_block_set && pair_mode_active() && info.getIdAddress() == s_pm_block) {   // V3.7.8\n'
      '      Serial.println("[AVO BLE] modo vincular: el telefono anterior se rechaza hasta que se vincule el nuevo");\n'
      '      server->disconnect(info.getConnHandle());\n'
      '      return;\n'
      '    }\n')

# ---------------------------------------------------------------- controller: triple click
CTL = SRC / 'controller.cpp'
patch(CTL,
      '    case BootButton::DOUBLE:\n',
      '    case BootButton::TRIPLE:   // V3.7.8: "connect a phone" mode (a second triple click closes it)\n'
      '      s_confirm_stop = false;\n'
      '      ble::pair_mode(!ble::pair_mode_active());\n'
      '      break;\n'
      '    case BootButton::DOUBLE:\n')

# ---------------------------------------------------------------- screen
patch(SRC / 'ui_model.cpp',
      'set(c.state, sizeof c.state, ok ? "Conectado" : s.ble.claim_pending ? "PULSA BOOT" :',
      'set(c.state, sizeof c.state, s.ble.pair_mode ? "MODO VINCULAR" : ok ? "Conectado" : s.ble.claim_pending ? "PULSA BOOT" :')

print('apply_v378: OK (BOOT x3 -> pair mode 120 s: drop/block current phone, advertise, auto-confirm CLAIM)')
