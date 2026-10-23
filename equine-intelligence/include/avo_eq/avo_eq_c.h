/* AVO Equine Intelligence Engine — C API (stable ABI for Android JNI, Windows P/Invoke and Python ctypes).
 * One implementation of the mathematics for every platform. All strings are UTF-8. */
#ifndef AVO_EQ_C_H
#define AVO_EQ_C_H
#ifdef __cplusplus
extern "C" {
#endif

#if defined(AVO_EQ_STATIC)
#  define AVO_EQ_API
#elif defined(_WIN32)
#  if defined(AVO_EQ_BUILD_DLL)
#    define AVO_EQ_API __declspec(dllexport)
#  else
#    define AVO_EQ_API __declspec(dllimport)
#  endif
#else
#  define AVO_EQ_API __attribute__((visibility("default")))
#endif

/* Engine version, e.g. "1.0.0-dev1". Static string, do not free. */
AVO_EQ_API const char* avo_eq_version(void);

/* Analyses one session made of n RAW segment files (in order).
 * processed_at_utc: ISO-8601 text stored in the result (may be NULL). include_series: 0/1.
 * On success returns 0 and *json_out points to a heap string the caller releases with avo_eq_free().
 * On error returns non-zero and *json_out holds {"error": "..."} (also released with avo_eq_free). */
AVO_EQ_API int avo_eq_analyse_files(const char* const* paths, int n, const char* processed_at_utc, int include_series, char** json_out);

/* CSV exports of the same analysis (gnss, aires, cadencia). which: 0 gnss, 1 gait, 2 cadence. */
AVO_EQ_API int avo_eq_export_csv(const char* const* paths, int n, int which, char** csv_out);

/* Fundamental (cycle) frequency of a uniformly sampled signal; returns 0 if none. strength may be NULL. */
AVO_EQ_API double avo_eq_fundamental(const double* x, int n, double fs, double f_min, double f_max, double* strength);

AVO_EQ_API void avo_eq_free(char* p);

#ifdef __cplusplus
}
#endif
#endif
