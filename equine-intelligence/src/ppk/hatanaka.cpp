// Hatanaka (Compact RINEX 3.0) → RINEX 3 observation file. Own implementation written from the format description:
// Hatanaka, Y. (2008), A Compression Format and Tools for GNSS Observation Data, Bulletin of the Geospatial
// Information Authority of Japan, 55, 21-30. The IGN publishes its ERGNSS RINEX 3 files as CRINEX + gzip.
//
// Format (CRINEX 3.0):
//  - 2 extra header lines (CRINEX VERS / TYPE, CRINEX PROG / DATE), then the RINEX header unchanged.
//  - Per epoch: an epoch line (initialised when it starts with '>', otherwise character differences against the
//    previous one: ' ' = unchanged, '&' = space), its first 41 columns are the RINEX epoch record and the satellite
//    list follows from column 42; then the receiver clock line (empty, "n&value" or a difference); then one line per
//    satellite: one field per observation type of its system, separated by one space (empty = missing), "n&v"
//    starts a difference arc of order n with value v, otherwise the field is the n-th order difference; values are
//    integers in units of 0.001; after the last field and one space, the LLI/SSI characters (difference text again).
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <string>
#include <vector>
#include "avo_eq/ppk.h"

namespace avoeq {

namespace {

struct Arc {
  int order = -1;   // -1: not initialised (next value must be "n&v")
  int k = 0;        // differences accumulated so far (<= order)
  int64_t d[10] = {0};
};

// Applies a new value (difference or initialisation) and returns the reconstructed observation.
bool arc_apply(Arc* a, const std::string& f, int64_t* out) {
  size_t amp = f.find('&');
  if (amp != std::string::npos) {
    int ord = std::atoi(f.substr(0, amp).c_str());
    if (ord < 0 || ord > 9) return false;
    a->order = ord;
    a->k = 0;
    a->d[0] = std::strtoll(f.c_str() + amp + 1, nullptr, 10);
    *out = a->d[0];
    return true;
  }
  if (a->order < 0) return false;
  int64_t x = std::strtoll(f.c_str(), nullptr, 10);
  if (a->k < a->order) a->k++;
  int64_t nd[10];
  nd[a->k] = x;
  for (int j = a->k - 1; j >= 0; j--) nd[j] = a->d[j] + nd[j + 1];
  for (int j = 0; j <= a->k; j++) a->d[j] = nd[j];
  *out = a->d[0];
  return true;
}

void repair(std::string* old, const std::string& diff) {
  if (old->size() < diff.size()) old->resize(diff.size(), ' ');
  for (size_t i = 0; i < diff.size(); i++) {
    char c = diff[i];
    if (c == ' ') continue;
    (*old)[i] = c == '&' ? ' ' : c;
  }
}

// value in 0.001 units → F14.3
void put_f14_3(std::string* o, int64_t v) {
  char b[40];
  bool neg = v < 0;
  uint64_t u = neg ? (uint64_t)(-(v + 1)) + 1 : (uint64_t)v;
  std::snprintf(b, sizeof b, "%s%llu.%03llu", neg ? "-" : "", (unsigned long long)(u / 1000), (unsigned long long)(u % 1000));
  size_t n = std::strlen(b);
  if (n < 14) o->append(14 - n, ' ');
  o->append(b);
}

std::string rtrim(const std::string& s) {
  size_t e = s.find_last_not_of(" \r\n");
  return e == std::string::npos ? std::string() : s.substr(0, e + 1);
}

struct SatState {
  std::vector<Arc> arcs;
  std::string flags;
};

}  // namespace

bool is_crinex(const std::string& head) {
  size_t e = head.find('\n');
  std::string l = head.substr(0, e == std::string::npos ? head.size() : e);
  return l.find("CRINEX VERS") != std::string::npos;
}

bool crx_to_rnx(const std::string& crx, std::string* rnx, std::string* error) {
  auto fail = [&](const std::string& m) { if (error) *error = m; return false; };
  std::vector<std::string> lines;
  {
    size_t i = 0;
    while (i < crx.size()) {
      size_t e = crx.find('\n', i);
      if (e == std::string::npos) e = crx.size();
      std::string l = crx.substr(i, e - i);
      if (!l.empty() && l.back() == '\r') l.pop_back();
      lines.push_back(l);
      i = e + 1;
    }
  }
  if (lines.size() < 3 || lines[0].find("CRINEX VERS") == std::string::npos) return fail("no es CRINEX (Hatanaka)");
  if (lines[0].compare(0, 3, "3.0") != 0) return fail("versión CRINEX no admitida: " + lines[0].substr(0, 20) + " (solo 3.0)");
  std::string out;
  out.reserve(crx.size() * 3);
  // header
  std::map<char, int> ntypes;
  size_t li = 2;
  char cur_sys = 0;
  for (; li < lines.size(); li++) {
    const std::string& l = lines[li];
    out += l; out += '\n';
    std::string label = l.size() > 60 ? l.substr(60) : "";
    if (label.compare(0, 19, "SYS / # / OBS TYPES") == 0) {
      if (l[0] != ' ') { cur_sys = l[0]; ntypes[cur_sys] = std::atoi(l.substr(3, 3).c_str()); }
    }
    if (label.compare(0, 13, "END OF HEADER") == 0) { li++; break; }
  }
  (void)cur_sys;
  if (ntypes.empty()) return fail("cabecera sin SYS / # / OBS TYPES");
  std::string epoch;           // previous epoch line (reconstructed)
  Arc clk;
  std::map<std::string, SatState> sats;
  uint32_t nepochs = 0;
  while (li < lines.size()) {
    const std::string& el = lines[li++];
    if (el.empty() && li >= lines.size()) break;
    if (!el.empty() && el[0] == '>') { epoch = el; sats.clear(); clk = Arc(); }
    else if (!epoch.empty()) {
      std::string e = epoch;
      repair(&e, el);
      // a shorter difference line keeps the old tail; a satellite list that shrank is cut by the count below
      epoch = e;
    } else return fail("línea de época diferencial sin inicializar (línea " + std::to_string(li) + ")");
    if (epoch.size() < 35) return fail("línea de época corta (línea " + std::to_string(li) + ")");
    int flag = epoch[31] - '0';
    int nsat = std::atoi(epoch.substr(32, 3).c_str());
    if (flag >= 2 && flag <= 5) {   // event: n header records follow verbatim
      out += rtrim(epoch.substr(0, 35)); out += '\n';
      for (int i = 0; i < nsat && li < lines.size(); i++) { out += lines[li++]; out += '\n'; }
      epoch.clear();                // the next epoch line is an initialisation
      continue;
    }
    if (epoch.size() < 41 + (size_t)nsat * 3) return fail("lista de satélites incompleta (línea " + std::to_string(li) + ")");
    epoch.resize(41 + (size_t)nsat * 3);
    if (li >= lines.size()) return fail("falta la línea del reloj");
    const std::string& cl = lines[li++];
    std::string rec = epoch.substr(0, 35);
    if (!cl.empty()) {
      int64_t c;
      if (!arc_apply(&clk, rtrim(cl), &c)) return fail("reloj del receptor sin inicializar");
      char b[40];
      bool neg = c < 0;
      uint64_t u = neg ? (uint64_t)(-(c + 1)) + 1 : (uint64_t)c;
      std::snprintf(b, sizeof b, "%s%llu.%012llu", neg ? "-" : "", (unsigned long long)(u / 1000000000000ull), (unsigned long long)(u % 1000000000000ull));
      rec += "      ";
      size_t n = std::strlen(b);
      if (n < 15) rec.append(15 - n, ' ');
      rec += b;
    } else clk = Arc();
    out += rec; out += '\n';
    std::map<std::string, SatState> next;
    for (int s = 0; s < nsat; s++) {
      if (li >= lines.size()) return fail("faltan líneas de satélite");
      const std::string& dl = lines[li++];
      std::string id = epoch.substr(41 + (size_t)s * 3, 3);
      auto it = ntypes.find(id[0]);
      if (it == ntypes.end()) return fail("sistema sin tipos de observación: " + id);
      int nt = it->second;
      SatState st;
      auto old = sats.find(id);
      if (old != sats.end()) st = old->second;
      st.arcs.resize((size_t)nt);
      std::vector<bool> have((size_t)nt, false);
      std::vector<int64_t> val((size_t)nt, 0);
      size_t p = 0;
      int f = 0;
      for (; f < nt; f++) {
        if (p > dl.size()) break;
        size_t sp = dl.find(' ', p);
        std::string field = dl.substr(p, sp == std::string::npos ? std::string::npos : sp - p);
        p = sp == std::string::npos ? dl.size() + 1 : sp + 1;
        if (field.empty()) { st.arcs[(size_t)f] = Arc(); continue; }
        int64_t v;
        if (!arc_apply(&st.arcs[(size_t)f], field, &v)) return fail("dato diferencial sin inicializar: " + id + " (línea " + std::to_string(li) + ")");
        have[(size_t)f] = true; val[(size_t)f] = v;
      }
      for (; f < nt; f++) st.arcs[(size_t)f] = Arc();   // line ended: the remaining fields are missing
      std::string fl = p <= dl.size() ? dl.substr(p) : std::string();
      repair(&st.flags, fl);
      if (st.flags.size() < (size_t)nt * 2) st.flags.resize((size_t)nt * 2, ' ');
      std::string o = id;
      for (int k = 0; k < nt; k++) {
        if (have[(size_t)k]) put_f14_3(&o, val[(size_t)k]); else o.append(14, ' ');
        o += st.flags[(size_t)k * 2];
        o += st.flags[(size_t)k * 2 + 1];
      }
      out += rtrim(o); out += '\n';
      next[id] = st;
    }
    sats.swap(next);
    nepochs++;
  }
  if (!nepochs) return fail("CRINEX sin épocas");
  *rnx = std::move(out);
  return true;
}

}  // namespace avoeq
