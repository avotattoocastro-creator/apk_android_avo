#include "avo_eq/json.h"
#include <cstdio>
#include <cstdlib>

namespace avoeq {
namespace json {

static const Value& nul() { static const Value v; return v; }

const Value& Value::operator[](const std::string& k) const {
  if (type != OBJ) return nul();
  auto it = o.find(k);
  return it == o.end() ? nul() : it->second;
}
const Value& Value::operator[](size_t i) const { return (type == ARR && i < a.size()) ? a[i] : nul(); }

namespace {
struct P {
  const std::string& t; size_t i = 0; std::string err; int depth = 0;
  explicit P(const std::string& s) : t(s) {}
  void ws() { while (i < t.size() && (t[i] == ' ' || t[i] == '\n' || t[i] == '\r' || t[i] == '\t')) i++; }
  bool fail(const char* m) { if (err.empty()) err = std::string(m) + " en la posición " + std::to_string(i); return false; }
  static void utf8(std::string& o, unsigned cp) {
    if (cp < 0x80) o += (char)cp;
    else if (cp < 0x800) { o += (char)(0xC0 | (cp >> 6)); o += (char)(0x80 | (cp & 0x3F)); }
    else if (cp < 0x10000) { o += (char)(0xE0 | (cp >> 12)); o += (char)(0x80 | ((cp >> 6) & 0x3F)); o += (char)(0x80 | (cp & 0x3F)); }
    else { o += (char)(0xF0 | (cp >> 18)); o += (char)(0x80 | ((cp >> 12) & 0x3F)); o += (char)(0x80 | ((cp >> 6) & 0x3F)); o += (char)(0x80 | (cp & 0x3F)); }
  }
  bool hex4(unsigned* v) {
    if (i + 4 > t.size()) return fail("escape \\u incompleto");
    *v = 0;
    for (int k = 0; k < 4; k++) {
      char c = t[i++]; *v <<= 4;
      if (c >= '0' && c <= '9') *v |= c - '0'; else if (c >= 'a' && c <= 'f') *v |= c - 'a' + 10;
      else if (c >= 'A' && c <= 'F') *v |= c - 'A' + 10; else return fail("hexadecimal no válido");
    }
    return true;
  }
  bool str(std::string* o) {
    i++;  // opening quote
    while (i < t.size()) {
      char c = t[i++];
      if (c == '"') return true;
      if (c != '\\') { *o += c; continue; }
      if (i >= t.size()) break;
      char e = t[i++];
      switch (e) {
        case '"': *o += '"'; break; case '\\': *o += '\\'; break; case '/': *o += '/'; break;
        case 'b': *o += '\b'; break; case 'f': *o += '\f'; break; case 'n': *o += '\n'; break;
        case 'r': *o += '\r'; break; case 't': *o += '\t'; break;
        case 'u': {
          unsigned cp; if (!hex4(&cp)) return false;
          if (cp >= 0xD800 && cp < 0xDC00 && i + 6 <= t.size() && t[i] == '\\' && t[i + 1] == 'u') {
            i += 2; unsigned lo; if (!hex4(&lo)) return false;
            cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
          }
          utf8(*o, cp); break;
        }
        default: return fail("escape desconocido");
      }
    }
    return fail("cadena sin cerrar");
  }
  bool val(Value* v) {
    if (++depth > 200) return fail("anidamiento excesivo");
    ws();
    if (i >= t.size()) return fail("fin inesperado");
    char c = t[i];
    bool ok = true;
    if (c == '{') {
      v->type = Value::OBJ; i++; ws();
      if (i < t.size() && t[i] == '}') { i++; depth--; return true; }
      while (ok) {
        ws(); if (i >= t.size() || t[i] != '"') return fail("se esperaba una clave");
        std::string k; if (!str(&k)) return false;
        ws(); if (i >= t.size() || t[i] != ':') return fail("se esperaba ':'");
        i++;
        Value x; if (!val(&x)) return false;
        v->o[k] = std::move(x);
        ws(); if (i < t.size() && t[i] == ',') { i++; continue; }
        if (i < t.size() && t[i] == '}') { i++; break; }
        return fail("se esperaba ',' o '}'");
      }
    } else if (c == '[') {
      v->type = Value::ARR; i++; ws();
      if (i < t.size() && t[i] == ']') { i++; depth--; return true; }
      while (true) {
        Value x; if (!val(&x)) return false;
        v->a.push_back(std::move(x));
        ws(); if (i < t.size() && t[i] == ',') { i++; continue; }
        if (i < t.size() && t[i] == ']') { i++; break; }
        return fail("se esperaba ',' o ']'");
      }
    } else if (c == '"') {
      v->type = Value::STR; if (!str(&v->s)) return false;
    } else if (t.compare(i, 4, "true") == 0) { v->type = Value::BOOL; v->b = true; i += 4; }
    else if (t.compare(i, 5, "false") == 0) { v->type = Value::BOOL; v->b = false; i += 5; }
    else if (t.compare(i, 4, "null") == 0) { v->type = Value::NUL; i += 4; }
    else {
      const char* s0 = t.c_str() + i; char* e = nullptr;
      double d = std::strtod(s0, &e);
      if (e == s0) return fail("valor no reconocido");
      v->type = Value::NUM; v->n = d; i += (size_t)(e - s0);
    }
    depth--;
    return ok;
  }
};
}  // namespace

bool parse(const std::string& text, Value* out, std::string* err) {
  P p(text);
  *out = Value();
  bool ok = p.val(out);
  if (ok) { p.ws(); if (p.i != text.size()) ok = p.fail("texto sobrante"); }
  if (!ok && err) *err = p.err;
  return ok;
}

std::string escape(const std::string& s) {
  std::string o;
  for (char ch : s) {
    switch (ch) {
      case '"': o += "\\\""; break; case '\\': o += "\\\\"; break; case '\n': o += "\\n"; break;
      case '\r': o += "\\r"; break; case '\t': o += "\\t"; break;
      default: if ((unsigned char)ch < 0x20) { char b[8]; snprintf(b, sizeof(b), "\\u%04x", ch); o += b; } else o += ch;
    }
  }
  return o;
}

}  // namespace json
}  // namespace avoeq
