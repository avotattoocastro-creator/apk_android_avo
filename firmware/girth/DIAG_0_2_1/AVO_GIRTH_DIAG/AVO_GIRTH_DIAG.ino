/* AVO PERFORMANCE HORSE — GIRTH (cincha) · DIAGNÓSTICO 0.2.1-diag · XIAO ESP32-C6 + BNO085 (GY-BNO08X)
 *
 * Firmware SOLO de diagnóstico del montaje BNO085 ↔ XIAO (puentes D0–D6, VCC/GND). No usa la radio,
 * no toca la NVS (el emparejamiento con la espalda se conserva). Después se vuelve a instalar el firmware normal.
 *
 * Cableado esperado (hardware/girth/REV5, esquema cableado_bno_c6.png):
 *   PS0+PS1–D0(GPIO0) · RST–D1(GPIO1) · INT–D2(GPIO2) · CS–D3(GPIO21) · ADD–D4(GPIO22) · SDA–D5(GPIO23) · SCL–D6(GPIO16)
 *   VCC→3V3 y GND→GND (pads de la cara inferior). Divisor de batería en MTDI (GPIO5).
 *
 * Cada 15 s repite y escribe por el monitor serie USB (AVO Update):
 *   1) niveles de cada línea con pull-up / pull-down internos (detecta resistencias de la placa del BNO = le llega VCC,
 *      líneas sueltas y líneas a GND);
 *   2) cortocircuitos entre líneas vecinas (pone una a LOW/HIGH y mira las demás; INT no se fuerza nunca);
 *   3) arranque del BNO en modo I²C: RST → INT debe bajar (el BNO ha arrancado);
 *   4) búsqueda I²C en SDA 23 / SCL 16 a 100 y 400 kHz, y con SDA/SCL intercambiados;
 *   5) si el I²C no responde: arranque en modo SPI y lectura de la cabecera SHTP;
 *   6) tensión en GPIO5 (batería con divisor 1:2);
 *   7) un resumen con la causa más probable.
 * Nada de esto declara el montaje validado: son medidas eléctricas para localizar el fallo.
 */
#include <Arduino.h>
#include <Wire.h>
#include <SPI.h>

#define DIAG_VERSION "0.2.1-diag"
// Marca de identidad que lee AVO Update (versión seguida de "AVO-GIRTH"): solo se instala en la cincha ESP32-C6.
extern "C" const char AVO_GIRTH_IMAGE_ID[] __attribute__((used, aligned(4))) = "\0" DIAG_VERSION "\0AVO-GIRTH";

struct Line { const char* bno; const char* xiao; int gpio; bool driveable; };
static const Line L[] = {
  {"PS0/PS1", "D0", 0, true}, {"RST", "D1", 1, true}, {"INT", "D2", 2, false}, {"CS", "D3", 21, true},
  {"ADD", "D4", 22, true},    {"SDA", "D5", 23, true}, {"SCL", "D6", 16, true}};
static const int N = sizeof(L) / sizeof(L[0]);
enum { PS = 0, RST = 1, INT_ = 2, CS = 3, ADD = 4, SDA_ = 5, SCL_ = 6 };
static const int LED_PIN = 15, BAT_PIN = 5;

static int pdLevel[N], puLevel[N];
static int shorts = 0;

static void releaseAll() {
  for (int i = 0; i < N; i++) pinMode(L[i].gpio, INPUT);
}

static int readWith(int gpio, int mode) {
  pinMode(gpio, mode);
  delayMicroseconds(800);
  return digitalRead(gpio);
}

static void testLevels() {
  Serial.println("[DIAG] 1) Niveles de cada línea (el BNO funcionando libre):");
  releaseAll();
  delay(5);
  for (int i = 0; i < N; i++) {
    pdLevel[i] = readWith(L[i].gpio, INPUT_PULLDOWN);
    puLevel[i] = readWith(L[i].gpio, INPUT_PULLUP);
    pinMode(L[i].gpio, INPUT);
    const char* v;
    if (pdLevel[i] == 1 && puLevel[i] == 1) v = "ALTO con pull-down → resistencia a VCC en el BNO (le llega VCC y el puente conecta)";
    else if (pdLevel[i] == 0 && puLevel[i] == 0) v = "BAJO con pull-up → resistencia a GND en el BNO o línea a GND";
    else v = "sigue al pull interno → sin resistencia externa (línea suelta o pin de entrada del BNO)";
    Serial.printf("    %-7s (%s, GPIO%-2d): pull-down=%d pull-up=%d  %s\n", L[i].bno, L[i].xiao, L[i].gpio, pdLevel[i],
                  puLevel[i], v);
  }
  for (int g : {0, 1, 2}) {
    pinMode(g, INPUT);
    delay(2);
    Serial.printf("    GPIO%d sin pull: %u mV\n", g, (unsigned)analogReadMilliVolts(g));
    pinMode(g, INPUT);
  }
}

static void testShorts() {
  Serial.println("[DIAG] 2) Cortocircuitos entre líneas (INT nunca se fuerza):");
  shorts = 0;
  for (int i = 0; i < N; i++) {
    if (!L[i].driveable) continue;
    for (int lvl = 0; lvl <= 1; lvl++) {
      for (int j = 0; j < N; j++)
        if (j != i) pinMode(L[j].gpio, lvl == 0 ? INPUT_PULLUP : INPUT_PULLDOWN);
      pinMode(L[i].gpio, OUTPUT);
      digitalWrite(L[i].gpio, lvl);
      delayMicroseconds(800);
      for (int j = 0; j < N; j++) {
        if (j == i) continue;
        int r = digitalRead(L[j].gpio);
        int base = lvl == 0 ? puLevel[j] : pdLevel[j];
        if (r == lvl && base != lvl) {
          Serial.printf("    CORTO: %s (%s) ↔ %s (%s) — al poner %s a %s, %s también cambia\n", L[i].bno, L[i].xiao, L[j].bno,
                        L[j].xiao, L[i].xiao, lvl ? "HIGH" : "LOW", L[j].xiao);
          shorts++;
        }
      }
      pinMode(L[i].gpio, INPUT);
    }
  }
  releaseAll();
  if (!shorts) Serial.println("    ninguno detectado");
}

// Arranca el BNO: PS0/PS1 = mode (LOW = I²C, HIGH = SPI). Devuelve ms hasta que INT baja, o -1.
static int bootBno(int psLevel) {
  pinMode(L[PS].gpio, OUTPUT);  digitalWrite(L[PS].gpio, psLevel);
  pinMode(L[ADD].gpio, OUTPUT); digitalWrite(L[ADD].gpio, LOW);
  pinMode(L[CS].gpio, OUTPUT);  digitalWrite(L[CS].gpio, HIGH);
  pinMode(L[INT_].gpio, INPUT_PULLUP);
  pinMode(L[RST].gpio, OUTPUT); digitalWrite(L[RST].gpio, LOW);
  delay(20);
  int intInReset = digitalRead(L[INT_].gpio);
  digitalWrite(L[RST].gpio, HIGH);
  uint32_t t0 = millis();
  int ms = -1;
  while (millis() - t0 < 1500) {
    if (digitalRead(L[INT_].gpio) == LOW) { ms = millis() - t0; break; }
    delay(1);
  }
  Serial.printf("    modo %s: INT durante el reset=%d, INT baja tras soltar RST: %s", psLevel ? "SPI" : "I2C", intInReset,
                ms >= 0 ? "SÍ" : "NO (en 1,5 s)");
  if (ms >= 0) Serial.printf(" a los %d ms", ms);
  Serial.println();
  return ms;
}

static int scan(int sda, int scl, uint32_t hz, bool quiet = false) {
  Wire.end();
  pinMode(sda, INPUT_PULLUP); pinMode(scl, INPUT_PULLUP);
  delay(1);
  int sdaIdle = digitalRead(sda), sclIdle = digitalRead(scl);
  Wire.begin(sda, scl, hz);
  Wire.setTimeOut(20);
  int found = 0, first = -1;
  char list[200] = "";
  for (int a = 0x08; a < 0x78; a++) {
    Wire.beginTransmission(a);
    if (Wire.endTransmission() == 0) {
      found++;
      if (first < 0) first = a;
      char b[8]; snprintf(b, sizeof b, " 0x%02X", a); strncat(list, b, sizeof list - strlen(list) - 1);
    }
  }
  Wire.end();
  if (!quiet)
    Serial.printf("    SDA=GPIO%d SCL=GPIO%d %3lu kHz: reposo SDA=%d SCL=%d · responden:%s\n", sda, scl, (unsigned long)(hz / 1000),
                  sdaIdle, sclIdle, found ? list : " ninguna dirección");
  return found ? first : -1;
}

static bool trySpi() {
  int ms = bootBno(HIGH);
  SPI.begin(L[SCL_].gpio /*SCK*/, L[SDA_].gpio /*MISO*/, L[ADD].gpio /*MOSI*/, L[CS].gpio /*CS*/);
  pinMode(L[CS].gpio, OUTPUT);
  digitalWrite(L[CS].gpio, HIGH);
  uint8_t h[4];
  SPI.beginTransaction(SPISettings(1000000, MSBFIRST, SPI_MODE3));
  digitalWrite(L[CS].gpio, LOW);
  for (int i = 0; i < 4; i++) h[i] = SPI.transfer(0x00);
  digitalWrite(L[CS].gpio, HIGH);
  SPI.endTransaction();
  SPI.end();
  uint16_t len = (h[0] | (h[1] << 8)) & 0x7FFF;
  bool ok = !(h[0] == 0xFF && h[1] == 0xFF) && !(h[0] == 0 && h[1] == 0) && len > 4 && len < 2048;
  Serial.printf("    SPI cabecera SHTP: %02X %02X %02X %02X (longitud %u, canal %u) → %s\n", h[0], h[1], h[2], h[3], len, h[2],
                ok ? "EL BNO RESPONDE POR SPI" : "sin respuesta válida");
  (void)ms;
  return ok;
}

static void runDiag() {
  static uint32_t pass = 0;
  Serial.printf("\n[DIAG] ===== AVO GIRTH %s · pasada %lu =====\n", DIAG_VERSION, (unsigned long)++pass);
  Wire.end();
  testLevels();
  testShorts();

  Serial.println("[DIAG] 3) Arranque del BNO:");
  int bootI2c = bootBno(LOW);
  delay(50);

  Serial.println("[DIAG] 4) Búsqueda I2C:");
  int a100 = scan(L[SDA_].gpio, L[SCL_].gpio, 100000);
  int a400 = scan(L[SDA_].gpio, L[SCL_].gpio, 400000);
  int aSwap = scan(L[SCL_].gpio, L[SDA_].gpio, 100000);   // SDA y SCL intercambiados
  bool spiOk = false;
  if (a100 < 0 && a400 < 0) {
    Serial.println("[DIAG] 5) Prueba por SPI (el I2C no responde):");
    spiOk = trySpi();
    bootBno(LOW);   // lo deja otra vez en modo I2C
  }

  uint32_t bat = 0;
  for (int i = 0; i < 8; i++) bat += analogReadMilliVolts(BAT_PIN);
  bat = bat / 8 * 2;
  Serial.printf("[DIAG] 6) Batería en GPIO5 (divisor 1:2): %lu mV%s\n", (unsigned long)bat,
                bat < 2500 ? "  → divisor sin montar o batería desconectada" : "");

  Serial.println("[DIAG] 7) RESUMEN:");
  int addr = a100 >= 0 ? a100 : a400;
  if (addr == 0x4A) Serial.println("    BNO085 OK por I2C en 0x4A: el montaje está bien; el fallo estaría en el firmware.");
  else if (addr == 0x4B) Serial.println("    El BNO responde en 0x4B, no en 0x4A: el puente ADD–D4 no conecta (ADD queda en HIGH).");
  else if (addr >= 0) Serial.printf("    Responde algo en 0x%02X pero no el BNO: revisa los puentes SDA/SCL.\n", addr);
  else if (aSwap >= 0) Serial.println("    Responde con SDA y SCL intercambiados: los puentes de SDA y SCL están cruzados.");
  else if (spiOk) Serial.println("    Responde por SPI pero no por I2C: el puente PS0/PS1–D0 no conecta, o SDA/SCL no llegan.");
  else if (pdLevel[SDA_] == 0 && pdLevel[SCL_] == 0)
    Serial.println("    SDA y SCL sin resistencia a VCC: al BNO NO le llega VCC (mide VCC–GND en el BNO: 3,3 V), o esos 2 puentes no conectan.");
  else if (bootI2c < 0)
    Serial.println("    INT no baja tras el reset: el BNO no arranca (VCC/GND, puente RST–D1 o INT–D2, o el BNO está dañado).");
  else Serial.println("    El BNO arranca (INT baja) pero no contesta por I2C ni por SPI: revisa PS0/PS1–D0 y los puentes SDA–D5 / SCL–D6.");
  if (shorts) Serial.println("    ¡Hay cortos entre líneas! Arréglalos primero (ver apartado 2).");
}

void setup() {
  Serial.begin(115200);
  uint32_t t0 = millis();
  while (!Serial && millis() - t0 < 3000) delay(10);
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, HIGH);
  analogReadResolution(12);
  Serial.printf("\n[AVO] AVO-GIRTH %s ready — diagnóstico del BNO085 (sin radio)\n", DIAG_VERSION);
}

void loop() {
  static uint32_t last = 0;
  if (last == 0 || millis() - last >= 15000) {
    last = millis();
    digitalWrite(LED_PIN, LOW);
    runDiag();
    digitalWrite(LED_PIN, HIGH);
  }
  delay(20);
}
