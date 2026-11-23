// AVO CASCO — la «espalda» dentro del casco: BackCore de la espalda 3.15.0 (ZED-F9P + GirthHub) sin cambios,
// unido al enlace del pecho por memoria en lugar de por ESP-NOW.
//
//   pecho (uart_link.cpp) ──tramas AVO UART v1 en paquetes ESP-NOW──> to_back()  ──> BackCore::on_radio
//   BackCore::radio_send(MAC virtual del pecho) ──────────────────────> uartlink::loopback_rx ──> decodificador del pecho
//   cinchas ──ESP-NOW real──> on_air() ──> BackCore::on_radio (GirthHub)
//
// Los contratos binarios (tramas, BackStatus v4, lotes de cincha, TELEMETRY v3, .avr) no cambian: son los mismos
// bytes que viajaban por radio entre el pecho y la espalda.
#pragma once
#include <stdint.h>
#include <stddef.h>

namespace casco_back {

// MAC virtuales del enlace interno (bit «administrado localmente»: nunca chocan con una MAC real).
extern const uint8_t kVirtualChest[6];
extern const uint8_t kVirtualBack[6];
uint32_t pair_id();   // el mismo en los dos lados, derivado de la MAC del chip

bool init();          // después de uartlink::init (ESP-NOW ya iniciado)
// Paquete ESP-NOW que el pecho «envía» a la espalda (lo llama el TX del pecho). Nunca bloquea.
bool to_back(const uint8_t* d, size_t n);
// Paquete recibido por la radio (cinchas). Lo llama el callback de ESP-NOW.
void on_air(const uint8_t mac[6], int8_t rssi, const uint8_t* d, int n);
// Resultado del envío real por radio (callback de ESP-NOW).
void on_air_sent(bool ok);
void set_battery_mv(uint16_t mv);
void power_off_peripherals();   // ZED (líneas a 0 primero), anillo y microSD

}  // namespace casco_back

// Lado del pecho (uart_link.cpp): entrada de los paquetes de la espalda interna.
namespace uartlink {
void loopback_rx(const uint8_t* mac, int8_t rssi, const uint8_t* d, int n);
}
