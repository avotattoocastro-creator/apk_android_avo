// Boceto mínimo de control para QEMU: mismas opciones de compilación que la cincha, sin periféricos.
// Si este boceto imprime y el de la cincha no, el bloqueo está en el firmware; si tampoco imprime, es QEMU/núcleo.
void setup() {
  Serial.begin(115200);
  Serial.println("[QEMU] minimo: setup");
}

void loop() {
  static unsigned n = 0;
  Serial.printf("[QEMU] minimo: loop %u\n", n++);
  delay(1000);
}
