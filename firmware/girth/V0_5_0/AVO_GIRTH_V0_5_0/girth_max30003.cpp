#include "girth_max30003.h"
#include <SPI.h>

namespace girth {

using namespace max30003;

static SPIClass s_spi(FSPI);
static const SPISettings kSpi(4000000, MSBFIRST, SPI_MODE0);
static TaskHandle_t s_notify = nullptr;
static void IRAM_ATTR on_intb() {
  BaseType_t hp = pdFALSE;
  if (s_notify) vTaskNotifyGiveFromISR(s_notify, &hp);
  if (hp) portYIELD_FROM_ISR();
}

uint32_t Max30003::rd(uint8_t reg) {
  s_spi.beginTransaction(kSpi);
  digitalWrite(p_.cs, LOW);
  s_spi.transfer(cmd(reg, true));
  uint32_t v = (uint32_t)s_spi.transfer(0) << 16;
  v |= (uint32_t)s_spi.transfer(0) << 8;
  v |= s_spi.transfer(0);
  digitalWrite(p_.cs, HIGH);
  s_spi.endTransaction();
  return v;
}

void Max30003::wr(uint8_t reg, uint32_t v) {
  s_spi.beginTransaction(kSpi);
  digitalWrite(p_.cs, LOW);
  s_spi.transfer(cmd(reg, false));
  s_spi.transfer((uint8_t)(v >> 16));
  s_spi.transfer((uint8_t)(v >> 8));
  s_spi.transfer((uint8_t)v);
  digitalWrite(p_.cs, HIGH);
  s_spi.endTransaction();
}

void Max30003::start_clock() {
  if (fclk_on_ || p_.fclk < 0) return;
  // 32 768 Hz square wave on FCLK (MAX30003 master clock) for modules without their own crystal
  if (ledcAttach(p_.fclk, 32768, 1)) { ledcWrite(p_.fclk, 1); fclk_on_ = true; }
}

void Max30003::stop_clock() {
  if (!fclk_on_) return;
  ledcDetach(p_.fclk);
  pinMode(p_.fclk, INPUT);
  fclk_on_ = false;
}

void Max30003::begin(const EcgPins& pins, QueueHandle_t out, uint8_t gain_code, int fclk_mode) {
  p_ = pins; out_ = out; gain_ = gain_code & 3; fclk_mode_ = fclk_mode;
  mtx_ = xSemaphoreCreateMutex();
  pinMode(p_.cs, OUTPUT);
  digitalWrite(p_.cs, HIGH);
  pinMode(p_.intb, INPUT_PULLUP);
  s_spi.begin(p_.sck, p_.miso, p_.mosi, -1);
  if (fclk_mode_ == 1) start_clock();
  xTaskCreate(task_entry, "ecg", 4096, this, 5, &task_);
}

EcgStatus Max30003::status() {
  EcgStatus s;
  xSemaphoreTake(mtx_, portMAX_DELAY);
  s = st_;
  s.fclk_generated = fclk_on_;
  xSemaphoreGive(mtx_);
  return s;
}

bool Max30003::start() {
  xSemaphoreTake(mtx_, portMAX_DELAY);
  st_.state = EcgState::STARTING; st_.starts++; st_.gain_code = gain_;
  xSemaphoreGive(mtx_);
  wr(SW_RST, 0);
  delay(5);
  uint32_t info = rd(INFO);
  if (info == 0 || info == 0xFFFFFF) {
    xSemaphoreTake(mtx_, portMAX_DELAY);
    st_.info = info; st_.state = EcgState::ERROR; st_.start_failures++;
    snprintf(st_.last_error, sizeof(st_.last_error), "no responde por SPI (INFO 0x%06lX)", (unsigned long)info);
    xSemaphoreGive(mtx_);
    return false;
  }
  wr(CNFG_GEN, cnfg_gen());
  wr(CNFG_CAL, 0);
  wr(CNFG_EMUX, 0);                 // inputs connected, no calibration, normal polarity
  wr(CNFG_ECG, cnfg_ecg(gain_));
  wr(CNFG_RTOR1, 0);                // R-R detection is done by the AVO engine on the raw ECG (2 ms resolution)
  wr(MNGR_INT, mngr_int(24));       // interrupt every 24 samples (~47 ms at 512 sps)
  wr(EN_INT, en_int());
  wr(FIFO_RST, 0);
  wr(SYNCH, 0);                     // start
  clock_.reset(1953.125);
  xSemaphoreTake(mtx_, portMAX_DELAY);
  st_.info = info; st_.state = EcgState::RUNNING; st_.last_error[0] = 0;
  xSemaphoreGive(mtx_);
  return true;
}

void Max30003::task_entry(void* self) { static_cast<Max30003*>(self)->task(); }

void Max30003::task() {
  s_notify = xTaskGetCurrentTaskHandle();
  attachInterrupt(digitalPinToInterrupt(p_.intb), on_intb, FALLING);
  uint32_t pause = 500;
  for (;;) {
    if (!start()) { delay(pause); pause = pause < 8000 ? pause * 2 : 8000; continue; }
    pause = 500;
    restart_ = false;
    uint32_t started_ms = millis(), last_sample_ms = millis(), sec_ms = millis(), sec_n = 0;
    int32_t mn = INT32_MAX, mx = INT32_MIN;
    bool running = true;
    while (running && !restart_) {
      ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(40));       // interrupt or 40 ms poll (an edge can be missed)
      uint32_t st = rd(STATUS);
      bool leads_off = (st & ST_DCLOFFINT) != 0;
      if (st & ST_EOVF) {                                // FIFO overflow: samples lost, new time origin
        wr(FIFO_RST, 0);
        clock_.gap();
        xSemaphoreTake(mtx_, portMAX_DELAY); st_.overflows++; xSemaphoreGive(mtx_);
        continue;
      }
      EcgBurst b;
      b.count = 0; b.leads_off = leads_off;
      for (int k = 0; k < ECG_BURST_MAX; k++) {
        EcgWord w = decode_fifo_word(rd(ECG_FIFO));
        if (w.etag == EMPTY) break;
        if (w.etag == OVERFLOW) { wr(FIFO_RST, 0); clock_.gap(); break; }
        bool ok = (w.etag == VALID || w.etag == VALID_EOF) && !leads_off;
        int32_t v = ok ? counts_to_duv(w.counts, gain_) : ECG_INVALID;
        b.duv[b.count++] = v;
        if (ok) { if (v < mn) mn = v; if (v > mx) mx = v; }
        if (w.etag == VALID_EOF || w.etag == FAST_EOF) break;
      }
      uint32_t now_ms = millis();
      if (b.count) {
        last_sample_ms = now_ms;
        b.t0_us = clock_.burst(micros(), b.count);
        b.period_us = (float)clock_.period_us();
        sec_n += b.count;
        uint32_t inv = 0;
        for (int k = 0; k < b.count; k++) if (b.duv[k] == ECG_INVALID) inv++;
        if (xQueueSend(out_, &b, 0) != pdTRUE) { xSemaphoreTake(mtx_, portMAX_DELAY); st_.dropped_queue += b.count; xSemaphoreGive(mtx_); }
        xSemaphoreTake(mtx_, portMAX_DELAY);
        st_.samples += b.count; st_.invalid += inv; st_.leads_off = leads_off; st_.last_duv = b.duv[b.count - 1];
        xSemaphoreGive(mtx_);
      }
      if (now_ms - sec_ms >= 1000) {
        xSemaphoreTake(mtx_, portMAX_DELAY);
        st_.rate_hz = sec_n * 1000.0f / (float)(now_ms - sec_ms);
        st_.p2p_duv = (mx >= mn) ? mx - mn : 0;
        st_.leads_off = leads_off;
        xSemaphoreGive(mtx_);
        sec_ms = now_ms; sec_n = 0; mn = INT32_MAX; mx = INT32_MIN;
      }
      // no samples at all: the chip has no master clock (module without crystal) -> generate it (auto mode) and restart
      if (now_ms - last_sample_ms > 1500) {
        if (fclk_mode_ == -1 && !fclk_on_ && now_ms - started_ms > 1500) {
          start_clock();
        } else {
          xSemaphoreTake(mtx_, portMAX_DELAY);
          st_.state = EcgState::ERROR; st_.start_failures++;
          snprintf(st_.last_error, sizeof(st_.last_error), "sin muestras (reloj FCLK %s)", fclk_on_ ? "generado" : "del modulo");
          xSemaphoreGive(mtx_);
        }
        running = false;
      }
    }
  }
}

}  // namespace girth
