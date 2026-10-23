// JNI bridge: org.avoperformance.horse.engine.AvoEquine.analyse(String[] segments, String processedAt, boolean series): String (JSON)
#include <jni.h>
#include <string>
#include <vector>
#include "avo_eq/avo_eq_c.h"

extern "C" JNIEXPORT jstring JNICALL
Java_org_avoperformance_horse_engine_AvoEquine_nativeAnalyse(JNIEnv* env, jclass, jobjectArray paths, jstring when, jboolean series) {
  jsize n = env->GetArrayLength(paths);
  std::vector<std::string> keep;
  for (jsize i = 0; i < n; i++) {
    jstring s = (jstring)env->GetObjectArrayElement(paths, i);
    const char* c = env->GetStringUTFChars(s, nullptr);
    keep.emplace_back(c);
    env->ReleaseStringUTFChars(s, c);
    env->DeleteLocalRef(s);
  }
  std::vector<const char*> ptr;
  for (auto& k : keep) ptr.push_back(k.c_str());
  const char* w = when ? env->GetStringUTFChars(when, nullptr) : nullptr;
  char* out = nullptr;
  avo_eq_analyse_files(ptr.data(), (int)ptr.size(), w, series ? 1 : 0, &out);
  if (w) env->ReleaseStringUTFChars(when, w);
  jstring res = env->NewStringUTF(out ? out : "{\"error\":\"sin resultado\"}");
  avo_eq_free(out);
  return res;
}

extern "C" JNIEXPORT jstring JNICALL
Java_org_avoperformance_horse_engine_AvoEquine_nativeVersion(JNIEnv* env, jclass) { return env->NewStringUTF(avo_eq_version()); }
