#include "girth_ads1292.h"
#include <SPI.h>

namespace girth {

using namespace ads1292;

static SPIClass s_spi(FSPI);
// Commands and registers: ≤ 1 MHz and 4 tCLK (≈ 8 µs at 512 kHz) between bytes. Data (RDATAC): 4 MHz.
static const SPISettings kCmd(1000000, MSBFIRST, SPI_MODE1);
static const SPISettings kData(4000000, MSBFIRST, SPI_MODE1);
static TaskHandle_t s_notify = nullptr;
static void IRAM_ATTR on_drdy() {
  BaseType_t hp = pdFALSE;
  if (s_notify) vTaskNotifyGiveFromISR(s_notify, &hp);
  if (hp) portYIELD_FROM_ISR();
}

void Ads1292::cmd(uint8_t op) {
  s_spi.beginTransaction(kCmd);
  digitalWrite(p_.cs, LOW);
  s_spi.transfer(op);
  delayMicroseconds(10);
  digitalWrite(p_.cs, HIGH);
  s_spi.endTransaction();
  delayMicroseconds(10);
}

void Ads1292::wreg(uint8_t reg, uint8_t v) {
  s_spi.beginTransaction(kCmd);
  digitalWrite(p_.cs, LOW);
  s_spi.transfer(WREG | reg); delayMicroseconds(10);
  s_spi.transfer(0x00); delayMicroseconds(10);        // one register
  s_spi.transfer(v); delayMicroseconds(10);
  digitalWrite(p_.cs, HIGH);
  s_spi.endTransaction();
  delayMicroseconds(10);
}

uint8_t Ads1292::rreg(uint8_t reg) {
  s_spi.beginTransaction(kCmd);
  digitalWrite(p_.cs, LOW);
  s_spi.transfer(RREG | reg); delayMicroseconds(10);
  s_spi.transfer(0x00); delayMicroseconds(10);
  uint8_t v = s_spi.transfer(0x00); delayMicroseconds(10);
  digitalWrite(p_.cs, HIGH);
  s_spi.endTransaction();
  delayMicroseconds(10);
  return v;
}

void Ads1292::begin(const EcgPins& pins, QueueHandle_t out, uint8_t gain_code) {
  p_ = pins; out_ = out; gain_ = gain_code & 7;
  mtx_ = xSemaphoreCreateMutex();
  pinMode(p_.cs, OUTPUT); digitalWrite(p_.cs, HIGH);
  pinMode(p_.start, OUTPUT); digitalWrite(p_.start, LOW);
  pinMode(p_.reset, OUTPUT); digitalWrite(p_.reset, HIGH);
  pinMode(p_.drdy, INPUT_PULLUP);
  s_spi.begin(p_.sck, p_.miso, p_.mosi, -1);
  xTaskCreate(task_entry, "ecg", 4096, this, 5, &task_);
}

void Ads1292::power_down() {
  digitalWrite(p_.start, LOW);
  digitalWrite(p_.reset, LOW);                         // PWDN/RESET held low = power-down (≈ µW)
}

EcgStatus Ads1292::status() {
  EcgStatus s;
  xSemaphoreTake(mtx_, portMAX_DELAY);
  s = st_;
  xSemaphoreGive(mtx_);
  return s;
}

bool Ads1292::start() {
  xSemaphoreTake(mtx_, portMAX_DELAY);
  st_.state = EcgState::STARTING; st_.starts++; st_.gain_code = gain_;
  xSemaphoreGive(mtx_);
  digitalWrite(p_.start, LOW);
  // reset pulse (≥ 2 tCLK), then 18 tCLK; the power-on reset needs 2^18 tCLK (≈ 0,5 s) after the supply comes up
  digitalWrite(p_.reset, HIGH);
  if (st_.starts == 1) delay(600);
  digitalWrite(p_.reset, LOW); delayMicroseconds(50);
  digitalWrite(p_.reset, HIGH); delay(2);
  cmd(SDATAC);                                       // the device wakes up in RDATAC: stop it to write registers
  uint8_t id = rreg(ID);
  if (!id_ok(id)) {
    xSemaphoreTake(mtx_, portMAX_DELAY);
    st_.id = id; st_.state = EcgState::ERROR; st_.start_failures++;
    snprintf(st_.last_error, sizeof(st_.last_error), "no responde por SPI (ID 0x%02X)", id);
    xSemaphoreGive(mtx_);
    return false;
  }
  wreg(CONFIG2, config2()); delay(2);                // reference buffer first (it needs time to settle)
  wreg(CONFIG1, config1());
  wreg(LOFF, loff());
  wreg(CH1SET, ch1set());
  wreg(CH2SET, ch2set(gain_));
  wreg(RLD_SENS, rld_sens());
  wreg(LOFF_SENS, loff_sens());
  wreg(RESP1, resp1());
  wreg(RESP2, resp2());
  if (rreg(CH2SET) != ch2set(gain_) || rreg(CONFIG1) != config1()) {
    xSemaphoreTake(mtx_, portMAX_DELAY);
    st_.state = EcgState::ERROR; st_.start_failures++;
    snprintf(st_.last_error, sizeof(st_.last_error), "registros no se quedan escritos");
    xSemaphoreGive(mtx_);
    return false;
  }
  cmd(RDATAC);
  clock_.reset(2000.0);
  digitalWrite(p_.start, HIGH);                      // conversions start; DRDY every 2 ms
  xSemaphoreTake(mtx_, portMAX_DELAY);
  st_.id = id; st_.state = EcgState::RUNNING; st_.last_error[0] = 0;
  xSemaphoreGive(mtx_);
  return true;
}

void Ads1292::task_entry(void* self) { static_cast<Ads1292*>(self)->task(); }

void Ads1292::task() {
  s_notify = xTaskGetCurrentTaskHandle();
  attachInterrupt(digitalPinToInterrupt(p_.drdy), on_drdy, FALLING);
  uint32_t pause = 500;
  for (;;) {
    if (!start()) { delay(pause); pause = pause < 8000 ? pause * 2 : 8000; continue; }
    pause = 500;
    restart_ = false;
    EcgBurst b;
    b.count = 0; b.leads_off = false;
    uint32_t sec_ms = millis(), sec_n = 0, last_ms = millis();
    int32_t mn = INT32_MAX, mx = INT32_MIN;
    while (!restart_) {
      if (ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(200)) == 0 && digitalRead(p_.drdy) == HIGH) {
        // no DRDY for 200 ms: the converter stopped (supply dip, ESD): start again
        xSemaphoreTake(mtx_, portMAX_DELAY); st_.stalls++; xSemaphoreGive(mtx_);
        break;
      }
      uint32_t t_us = micros();
      uint8_t f[9];
      s_spi.beginTransaction(kData);
      digitalWrite(p_.cs, LOW);
      for (int k = 0; k < 9; k++) f[k] = s_spi.transfer(0);
      digitalWrite(p_.cs, HIGH);
      s_spi.endTransaction();
      Frame fr = decode_frame(f);
      bool off = leads_off(fr.loff_stat);
      int32_t v = (!fr.header_ok || off) ? ECG_INVALID : ads_code_to_duv(fr.ch2, gain_);
      if (!fr.header_ok) { xSemaphoreTake(mtx_, portMAX_DELAY); st_.bad_frames++; xSemaphoreGive(mtx_); }
      b.duv[b.count++] = v;
      b.leads_off = b.leads_off || off;
      if (v != ECG_INVALID) { if (v < mn) mn = v; if (v > mx) mx = v; }
      sec_n++;
      if (b.count >= ECG_BURST_AT) {
        b.t0_us = clock_.burst(t_us, b.count);
        b.period_us = (float)clock_.period_us();
        uint32_t inv = 0;
        for (int k = 0; k < b.count; k++) if (b.duv[k] == ECG_INVALID) inv++;
        if (xQueueSend(out_, &b, 0) != pdTRUE) { xSemaphoreTake(mtx_, portMAX_DELAY); st_.dropped_queue += b.count; xSemaphoreGive(mtx_); }
        xSemaphoreTake(mtx_, portMAX_DELAY);
        st_.samples += b.count; st_.invalid += inv; st_.leads_off = off; st_.loff_stat = fr.loff_stat;
        st_.last_duv = b.duv[b.count - 1];
        xSemaphoreGive(mtx_);
        b.count = 0; b.leads_off = false;
      }
      uint32_t now = millis();
      last_ms = now;
      if (now - sec_ms >= 1000) {
        xSemaphoreTake(mtx_, portMAX_DELAY);
        st_.rate_hz = sec_n * 1000.0f / (float)(now - sec_ms);
        st_.p2p_duv = (mx >= mn) ? mx - mn : 0;
        xSemaphoreGive(mtx_);
        sec_ms = now; sec_n = 0; mn = INT32_MAX; mx = INT32_MIN;
      }
    }
    (void)last_ms;
    digitalWrite(p_.start, LOW);
    clock_.gap();
  }
}

}  // namespace girth
