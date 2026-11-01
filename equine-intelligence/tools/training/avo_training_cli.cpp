// avo_training_cli: AVO Training Analytics desde la línea de órdenes.
//   avo_training_cli historia.json [opciones.json] [--out salida.json]
//   avo_training_cli --resumen analisis.json [extra.json] [--out resumen.json]
#include <cstdio>
#include <cstring>
#include <fstream>
#include <sstream>
#include <string>
#include "avo_eq/avo_eq_c.h"

static bool slurp(const char* p, std::string* t) {
  std::ifstream f(p, std::ios::binary);
  if (!f) return false;
  std::ostringstream s; s << f.rdbuf(); *t = s.str(); return true;
}

int main(int argc, char** argv) {
  bool summary = false;
  const char* outp = nullptr;
  const char* files[2] = {nullptr, nullptr};
  int nf = 0;
  for (int i = 1; i < argc; i++) {
    if (!strcmp(argv[i], "--resumen")) summary = true;
    else if (!strcmp(argv[i], "--out") && i + 1 < argc) outp = argv[++i];
    else if (nf < 2) files[nf++] = argv[i];
  }
  if (nf < 1) {
    fprintf(stderr, "uso: %s historia.json [opciones.json] [--out salida.json]\n     %s --resumen analisis.json [extra.json] [--out resumen.json]\n", argv[0], argv[0]);
    return 2;
  }
  std::string a, b;
  if (!slurp(files[0], &a)) { fprintf(stderr, "no se puede leer %s\n", files[0]); return 1; }
  if (files[1] && !slurp(files[1], &b)) { fprintf(stderr, "no se puede leer %s\n", files[1]); return 1; }
  char* json = nullptr;
  int rc = summary ? avo_eq_training_summary(a.c_str(), files[1] ? b.c_str() : nullptr, &json)
                   : avo_eq_training_analyse(a.c_str(), files[1] ? b.c_str() : nullptr, nullptr, &json);
  if (json) {
    if (outp) { std::ofstream f(outp, std::ios::binary); f << json; }
    else printf("%s\n", json);
    avo_eq_free(json);
  }
  return rc;
}
