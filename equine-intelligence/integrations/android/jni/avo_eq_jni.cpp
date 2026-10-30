// JNI bridge for org.avoperformance.horse.engine.AvoEquine (app module).
// Strings are passed as UTF-8 byte arrays in both directions: NewStringUTF/GetStringUTFChars use
// "modified UTF-8" and would corrupt (or abort on) characters outside the BMP in names or paths.
#include <jni.h>
#include <atomic>
#include <string>
#include <vector>
#include "avo_eq/avo_eq_c.h"

namespace {
std::string bytes_to_string(JNIEnv* env, jbyteArray a) {
  if (!a) return std::string();
  jsize n = env->GetArrayLength(a);
  std::string s((size_t)n, '\0');
  if (n) env->GetByteArrayRegion(a, 0, n, reinterpret_cast<jbyte*>(&s[0]));
  return s;
}
jbyteArray string_to_bytes(JNIEnv* env, const char* p) {
  std::string s = p ? p : "{\"error\":\"sin resultado\",\"codigo\":3}";
  jbyteArray a = env->NewByteArray((jsize)s.size());
  if (a && !s.empty()) env->SetByteArrayRegion(a, 0, (jsize)s.size(), reinterpret_cast<const jbyte*>(s.data()));
  return a;
}
std::vector<std::string> paths_of(JNIEnv* env, jobjectArray arr) {
  std::vector<std::string> v;
  jsize n = arr ? env->GetArrayLength(arr) : 0;
  for (jsize i = 0; i < n; i++) {
    jbyteArray b = (jbyteArray)env->GetObjectArrayElement(arr, i);
    v.push_back(bytes_to_string(env, b));
    env->DeleteLocalRef(b);
  }
  return v;
}
}  // namespace

extern "C" {

// cancel token: a heap int the Kotlin side can set from any thread while the analysis runs
JNIEXPORT jlong JNICALL Java_org_avoperformance_horse_engine_AvoEquine_nativeNewToken(JNIEnv*, jclass) { return (jlong)(intptr_t) new int(0); }
JNIEXPORT void JNICALL Java_org_avoperformance_horse_engine_AvoEquine_nativeCancel(JNIEnv*, jclass, jlong t) {
  if (t) __atomic_store_n((int*)(intptr_t)t, 1, __ATOMIC_SEQ_CST);
}
JNIEXPORT void JNICALL Java_org_avoperformance_horse_engine_AvoEquine_nativeFreeToken(JNIEnv*, jclass, jlong t) { delete (int*)(intptr_t)t; }

JNIEXPORT jbyteArray JNICALL Java_org_avoperformance_horse_engine_AvoEquine_nativeAnalyse(JNIEnv* env, jclass, jobjectArray paths, jbyteArray options, jlong token) {
  std::vector<std::string> keep = paths_of(env, paths);
  std::vector<const char*> ptr; for (auto& k : keep) ptr.push_back(k.c_str());
  std::string opt = bytes_to_string(env, options);
  char* out = nullptr;
  avo_eq_analyse_ex(ptr.data(), (int)ptr.size(), opt.c_str(), (const volatile int*)(intptr_t)token, &out);
  jbyteArray res = string_to_bytes(env, out);
  avo_eq_free(out);
  return res;
}

JNIEXPORT jbyteArray JNICALL Java_org_avoperformance_horse_engine_AvoEquine_nativeCompare(JNIEnv* env, jclass, jobjectArray a, jobjectArray b, jbyteArray options, jlong token) {
  std::vector<std::string> ka = paths_of(env, a), kb = paths_of(env, b);
  std::vector<const char*> pa, pb; for (auto& k : ka) pa.push_back(k.c_str()); for (auto& k : kb) pb.push_back(k.c_str());
  std::string opt = bytes_to_string(env, options);
  char* out = nullptr;
  avo_eq_compare_ex(pa.data(), (int)pa.size(), pb.data(), (int)pb.size(), opt.c_str(), (const volatile int*)(intptr_t)token, &out);
  jbyteArray res = string_to_bytes(env, out);
  avo_eq_free(out);
  return res;
}

JNIEXPORT jint JNICALL Java_org_avoperformance_horse_engine_AvoEquine_nativeCacheInvalidate(JNIEnv* env, jclass, jbyteArray dir) {
  std::string d = bytes_to_string(env, dir);
  return avo_eq_cache_invalidate(d.c_str());
}

JNIEXPORT jbyteArray JNICALL Java_org_avoperformance_horse_engine_AvoEquine_nativeVersion(JNIEnv* env, jclass) { return string_to_bytes(env, avo_eq_version()); }
JNIEXPORT jint JNICALL Java_org_avoperformance_horse_engine_AvoEquine_nativeApiVersion(JNIEnv*, jclass) { return avo_eq_api_version(); }

}  // extern "C"
