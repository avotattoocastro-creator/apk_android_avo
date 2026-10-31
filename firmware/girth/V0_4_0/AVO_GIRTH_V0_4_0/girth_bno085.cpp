#include "girth_bno085.h"
#include <Wire.h>
#include <esp_timer.h>
#include <driver/gpio.h>

namespace girth {

static const size_t kChunk = 508;          // payload bytes per I²C read (+4 header bytes = 512)

void Bno085::begin(const BnoPins& pins, uint32_t interval_us, QueueHandle_t out_queue) {
  pins_ = pins;
  interval_us_ = interval_us;
  q_ = out_queue;
  mtx_ = xSemaphoreCreateMutex();
  asm_.set_sink(&Bno085::on_sample, this);
  // Highest application priority: the IMU must never wait for the radio.
  xTaskCreate(&Bno085::task_entry, "bno085", 6144, this, configMAX_PRIORITIES - 3, &th_);
}

void Bno085::task_entry(void* arg) { static_cast<Bno085*>(arg)->task(); }

void IRAM_ATTR Bno085::isr(void* arg) {
  Bno085* b = static_cast<Bno085*>(arg);
  b->int_us_ = (uint32_t)esp_timer_get_time();
  BaseType_t woken = pdFALSE;
  if (b->th_) vTaskNotifyGiveFromISR(b->th_, &woken);
  if (woken) portYIELD_FROM_ISR();
}

BnoStatus Bno085::status() {
  BnoStatus c;
  if (xSemaphoreTake(mtx_, pdMS_TO_TICKS(20)) == pdTRUE) { c = st_; xSemaphoreGive(mtx_); }
  return c;
}

void Bno085::fail(const char* why) {
  xSemaphoreTake(mtx_, portMAX_DELAY);
  st_.state = BnoState::ERROR;
  st_.last_error = why;
  xSemaphoreGive(mtx_);
  Serial.printf("[AVO CINCHA] IMU: %s\n", why);
}

void Bno085::hold_in_reset() {
  restart_req_ = true;
  if (th_) vTaskSuspend(th_);
  detach_int();
  Wire.end();
  pinMode(pins_.rst, OUTPUT);
  digitalWrite(pins_.rst, LOW);
}

// 0.4.1: only detach when attached (0.4.0 printed "GPIO isr service is not installed" on the first start)
void Bno085::detach_int() {
  if (attached_) { detachInterrupt(pins_.intn); attached_ = false; }
}

bool Bno085::wait_int_low(uint32_t ms) {
  uint32_t t0 = millis();
  while (millis() - t0 < ms) {
    if (digitalRead(pins_.intn) == LOW) return true;
    ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(5));
  }
  return digitalRead(pins_.intn) == LOW;
}

// SHTP over I²C: a read first returns the 4-byte header (length, channel, sequence). The cargo is then read
// in chunks; every chunk starts again with a 4-byte header that is discarded.
bool Bno085::read_packet(uint8_t* ch, size_t* len) {
  *len = 0;
  if (Wire.requestFrom((int)addr_, 4) != 4) { st_.i2c_errors++; return false; }
  uint8_t h[4];
  for (int i = 0; i < 4; i++) h[i] = Wire.read();
  uint16_t plen = (uint16_t)(h[0] | (h[1] << 8));
  if (plen == 0xFFFF) { st_.i2c_errors++; return false; }   // bus stuck high
  plen &= 0x7FFF;                                            // bit 15: continuation
  *ch = h[2];
  if (plen <= 4) return true;                               // nothing waiting
  size_t want = plen - 4, got = 0;
  while (got < want) {
    size_t n = want - got;
    if (n > kChunk) n = kChunk;
    size_t req = n + 4;
    if (Wire.requestFrom((int)addr_, (int)req) != (int)req) { st_.i2c_errors++; return false; }
    for (int i = 0; i < 4; i++) Wire.read();
    for (size_t i = 0; i < n; i++) {
      uint8_t b = Wire.read();
      if (got + i < sizeof(buf_)) buf_[got + i] = b;
    }
    got += n;
  }
  *len = want < sizeof(buf_) ? want : sizeof(buf_);
  return true;
}

bool Bno085::write_packet(uint8_t ch, const uint8_t* d, size_t n) {
  if (ch > 5) return false;
  uint16_t total = (uint16_t)(n + 4);
  Wire.beginTransmission(addr_);
  Wire.write((uint8_t)(total & 0xFF));
  Wire.write((uint8_t)(total >> 8));
  Wire.write(ch);
  Wire.write(seq_[ch]++);
  Wire.write(d, n);
  if (Wire.endTransmission(true) != 0) { st_.i2c_errors++; return false; }
  return true;
}

// Reads up to max_packets while INT is low. Returns packets read, -1 on an I²C error.
int Bno085::service(int max_packets) {
  int count = 0;
  while (count < max_packets && digitalRead(pins_.intn) == LOW) {
    uint8_t ch = 0;
    size_t n = 0;
    uint32_t t_int = int_us_;
    if (!read_packet(&ch, &n)) return -1;
    if (!n) break;
    asm_.on_packet(ch, buf_, n, t_int);
    count++;
  }
  return count;
}

void Bno085::on_sample(const Sample& s, void* ctx) {
  Bno085* b = static_cast<Bno085*>(ctx);
  if (b->q_ && xQueueSend(b->q_, &s, 0) != pdTRUE) b->st_.dropped_queue++;
  b->rate_count_++;
  b->last_sample_ms_ = millis();
  b->st_.last = s;
}

bool Bno085::start() {
  xSemaphoreTake(mtx_, portMAX_DELAY);
  st_.state = BnoState::STARTING;
  st_.starts++;
  xSemaphoreGive(mtx_);
  detach_int();
  Wire.end();
  memset(seq_, 0, sizeof(seq_));
  asm_.reset_state();
  asm_.product = ProductId();
  memset(asm_.feature_interval_us, 0, sizeof(asm_.feature_interval_us));

  // 1. Levels for I²C mode, then reset
  pinMode(pins_.ps, OUTPUT);  digitalWrite(pins_.ps, LOW);
  pinMode(pins_.add, OUTPUT); digitalWrite(pins_.add, LOW);
  pinMode(pins_.cs, OUTPUT);  digitalWrite(pins_.cs, HIGH);
  pinMode(pins_.intn, INPUT_PULLUP);
  pinMode(pins_.rst, OUTPUT); digitalWrite(pins_.rst, LOW);
  vTaskDelay(pdMS_TO_TICKS(10));
  digitalWrite(pins_.rst, HIGH);
  uint32_t t0 = millis();
  bool int_low = wait_int_low(600);
  st_.int_ms = int_low ? (int)(millis() - t0) : -1;
  if (!int_low) { fail("INT no baja tras el reset (el BNO no arranca: alimentación, RST o INT)"); return false; }

  // 2. I²C
  Wire.setBufferSize(kChunk + 4);
  if (!Wire.begin(pins_.sda, pins_.scl, hz_)) { fail("no se puede iniciar el I2C del ESP32"); return false; }
  Wire.setTimeOut(50);
  addr_ = 0;
  for (uint8_t a : {(uint8_t)0x4A, (uint8_t)0x4B}) {
    Wire.beginTransmission(a);
    if (Wire.endTransmission() == 0) { addr_ = a; break; }
  }
  st_.addr = addr_;
  st_.i2c_hz = hz_;
  if (!addr_) { fail("sin ACK en 0x4A ni 0x4B (SDA/SCL, PS0/PS1 o ADD)"); return false; }

  attachInterruptArg(digitalPinToInterrupt(pins_.intn), &Bno085::isr, this, FALLING);
  attached_ = true;
  int_us_ = (uint32_t)esp_timer_get_time();

  // 3. Start-up packets (advertisement, reset complete): read for up to 300 ms
  t0 = millis();
  while (millis() - t0 < 300) {
    if (service(8) < 0) { fail("error I2C leyendo los paquetes de arranque"); return false; }
    ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(20));
  }
  asm_.reset_flag = false;

  // 4. Product ID: proves that the SH-2 protocol answers, not only the I²C address
  uint8_t cmd[17];
  size_t n = build_product_id_request(cmd, sizeof(cmd));
  if (!write_packet(CH_CONTROL, cmd, n)) { fail("error I2C enviando la petición de identificación"); return false; }
  t0 = millis();
  while (!asm_.product.valid && millis() - t0 < 500) {
    if (service(8) < 0) { fail("error I2C leyendo la identificación"); return false; }
    ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(10));
  }
  if (!asm_.product.valid) { fail("SH-2 no responde a la petición de identificación (el ACK I2C solo no basta)"); return false; }

  // 5. Reports
  for (uint8_t id : {R_ACCEL, R_GYRO, R_MAG, R_LINACC, R_GAME_RV}) {
    n = build_set_feature(id, interval_us_, cmd, sizeof(cmd));
    if (!write_packet(CH_CONTROL, cmd, n)) { fail("error I2C activando los informes"); return false; }
    vTaskDelay(pdMS_TO_TICKS(5));
    service(4);
  }

  // 6. Samples must arrive
  uint32_t s0 = asm_.samples;
  t0 = millis();
  while (millis() - t0 < 1000) {
    if (service(16) < 0) { fail("error I2C leyendo las primeras muestras"); return false; }
    ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(20));
  }
  if (asm_.samples - s0 < 20) { fail("el BNO responde pero no entrega muestras del acelerómetro"); return false; }

  xSemaphoreTake(mtx_, portMAX_DELAY);
  st_.state = BnoState::RUNNING;
  st_.last_error = "-";
  st_.product = asm_.product;
  memcpy(st_.interval_us, asm_.feature_interval_us, sizeof(st_.interval_us));
  xSemaphoreGive(mtx_);
  const ProductId& p = asm_.product;
  Serial.printf("[AVO CINCHA] IMU: BNO085 en 0x%02X a %lu kHz, INT a los %d ms, SH-2 %u.%u.%u (pieza %lu, build %lu), "
                "%lu muestras en 1 s\n", addr_, (unsigned long)(hz_ / 1000), st_.int_ms, p.sw_major, p.sw_minor, p.patch,
                (unsigned long)p.part, (unsigned long)p.build, (unsigned long)(asm_.samples - s0));
  // 0.4.1: the BNO picks its nearest supported period (100 Hz asked -> ~125 Hz seen): show what it confirmed
  Serial.printf("[AVO CINCHA] IMU: periodo pedido %lu us; confirmado por el BNO: acc %lu, giro %lu, mag %lu, lin %lu, cuaternion %lu us\n",
                (unsigned long)interval_us_, (unsigned long)asm_.feature_interval_us[R_ACCEL], (unsigned long)asm_.feature_interval_us[R_GYRO],
                (unsigned long)asm_.feature_interval_us[R_MAG], (unsigned long)asm_.feature_interval_us[R_LINACC],
                (unsigned long)asm_.feature_interval_us[R_GAME_RV]);
  rate_t0_ = millis();
  rate_count_ = 0;
  last_sample_ms_ = millis();
  run_t0_us_ = esp_timer_get_time();
  run_s0_ = asm_.samples;
  return true;
}

void Bno085::run() {
  uint32_t err_streak = 0;
  for (;;) {
    ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(20));
    int r = service(16);
    if (r < 0) {
      if (++err_streak >= 5) { fail("errores I2C repetidos durante la lectura"); return; }
    } else {
      err_streak = 0;
    }
    if (asm_.reset_flag) {          // the BNO restarted by itself: configure it again
      asm_.reset_flag = false;
      fail("el BNO se ha reiniciado solo; se vuelve a configurar");
      return;
    }
    uint32_t now = millis();
    if (now - last_sample_ms_ > 1000) { fail("sin muestras durante 1 s"); return; }
    if (restart_req_) { restart_req_ = false; fail("reinicio pedido por el monitor"); return; }
    if (now - rate_t0_ >= 1000) {
      xSemaphoreTake(mtx_, portMAX_DELAY);
      st_.rate_hz = rate_count_ * 1000.0f / (float)(now - rate_t0_);
      // 0.4.2: long-run period (samples counted over the whole run: steady, unlike the per-packet timestamps)
      uint32_t ns = asm_.samples - run_s0_;
      if (ns >= 250) st_.period_us = (float)(esp_timer_get_time() - run_t0_us_) / (float)ns;
      st_.samples = asm_.samples; st_.lost = asm_.lost; st_.unknown = asm_.unknown; st_.resets_seen = asm_.resets_seen;
      memcpy(st_.interval_us, asm_.feature_interval_us, sizeof(st_.interval_us));
      xSemaphoreGive(mtx_);
      rate_t0_ = now;
      rate_count_ = 0;
    }
  }
}

void Bno085::task() {
  uint32_t pause_ms = 1000, fails = 0;
  for (;;) {
    if (start()) {
      fails = 0;
      pause_ms = 1000;
      run();
      st_.restarts_running++;
      st_.rate_hz = 0;
    } else {
      st_.start_failures++;
      fails++;
      if (fails >= 3) hz_ = (fails % 2) ? 100000 : 400000;   // try the slow bus too
    }
    detach_int();
    vTaskDelay(pdMS_TO_TICKS(pause_ms));
    if (pause_ms < 10000) pause_ms *= 2;
  }
}

}  // namespace girth
