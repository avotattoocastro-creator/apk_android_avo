#pragma once
#include <string>
#include <vector>
#include "avo_eq/types.h"

namespace avoeq {
// Reads the segments of one session (in order). Returns false only when the first file is not AVO RAW.
bool ingest_raw(const std::vector<std::string>& segments, Session* out, std::string* error);
}
