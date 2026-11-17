// Minimal JSON reader (options, cached analyses, trained-model files). No external dependency.
// Strict enough for files written by this engine and by ml/avo_ml.py; numbers are doubles.
#pragma once
#include <map>
#include <memory>
#include <string>
#include <vector>

namespace avoeq {
namespace json {

struct Value {
  enum Type { NUL, BOOL, NUM, STR, ARR, OBJ } type = NUL;
  bool b = false;
  double n = 0;
  std::string s;
  std::vector<Value> a;
  std::map<std::string, Value> o;

  bool is_null() const { return type == NUL; }
  const Value& operator[](const std::string& k) const;     // NUL value when missing
  const Value& operator[](size_t i) const;
  double num(double def = 0) const { return type == NUM ? n : def; }
  bool boolean(bool def = false) const { return type == BOOL ? b : def; }
  std::string str(const std::string& def = "") const { return type == STR ? s : def; }
  bool has(const std::string& k) const { return type == OBJ && o.count(k) > 0; }
};

// Returns false (and sets *err) on malformed input.
bool parse(const std::string& text, Value* out, std::string* err = nullptr);

// Escapes a string for embedding in JSON output.
std::string escape(const std::string& s);

}  // namespace json
}  // namespace avoeq
