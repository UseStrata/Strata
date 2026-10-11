// strata.hpp - C++ wrapper for libstrata (the C API is strata.h; this adds std::string and
// namespaces, nothing more). Header-only.
// Copyright © 2026 Connor Rutberg. GPL-3.0 with the Strata Embedding Exception
// (LICENSE-EMBEDDING.md): any program may use it, whatever its own license.
//
//     #include "strata.hpp"
//     if (!strata::check("game/main.strata")) std::cerr << strata::diagnostics();
//
// Returned std::strings are copies, so they stay valid after strata::reset().
#pragma once

#include <string>
#include "strata.h"

namespace strata {

inline std::string version()                      { return strata_version(); }
inline std::string diagnostics()                  { return strata_diagnostics(); }

inline bool check(const std::string& path)        { return strata_check(path.c_str()); }
inline bool check_source(const std::string& path, const std::string& source) {
    return strata_check_source(path.c_str(), source.c_str());
}

inline bool build(const std::string& target, bool release = false, bool force = false) {
    return strata_build(target.c_str(), release, force);
}
inline std::string output_path(const std::string& target) { return strata_output_path(target.c_str()); }

inline void set_libdir(const std::string& dir)    { strata_set_libdir(dir.c_str()); }
inline void reset()                               { strata_reset(); }

}  // namespace strata
