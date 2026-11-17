// Derived-results store. RAW session files are only READ (fingerprinted), never modified or moved.
// One file per (input fingerprint, parameters hash): no duplicates. A stored analysis is reused only when the
// engine version, every algorithm version, the input fingerprint and the parameters all match; otherwise it is
// recalculated and replaced. cache_invalidate() removes analyses made by other engine/algorithm versions.
#pragma once
#include <string>
#include <vector>
#include "avo_eq/engine.h"

namespace avoeq {

// FNV-1a 64 over each file's size and content, in order (hex). Empty string + *err on failure.
std::string fingerprint_files(const std::vector<std::string>& paths, std::string* err);

struct CacheResult {
  std::string json;                // analysis JSON (format v2, always with series)
  std::string state;               // ACIERTO | CALCULADO | RECALCULADO
  std::string path;                // stored file
};

// Analyses (or reuses) the session. when: processing date stored in new results. force: always recalculate.
bool analyse_cached(const std::vector<std::string>& segments, const std::string& cache_dir, const EngineConfig& c,
                    const std::string& when, bool force, CacheResult* out, std::string* err);

struct CacheEntry { std::string file, session, engine, processed_at, fingerprint, params; bool valid = false; };
std::vector<CacheEntry> cache_list(const std::string& cache_dir);
int cache_invalidate(const std::string& cache_dir);   // returns files removed (-1 on error)

}  // namespace avoeq
