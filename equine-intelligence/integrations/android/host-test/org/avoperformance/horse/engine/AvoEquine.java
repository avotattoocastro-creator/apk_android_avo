package org.avoperformance.horse.engine;

/** Host-JVM twin of the app's Kotlin AvoEquine object: same class name and native signatures, so the very same
 *  JNI bridge (jni/avo_eq_jni.cpp) is exercised on Linux CI without an Android device. */
public final class AvoEquine {
  static { System.loadLibrary("avo_equine_jni"); }
  public static native long nativeNewToken();
  public static native void nativeCancel(long token);
  public static native void nativeFreeToken(long token);
  public static native byte[] nativeAnalyse(byte[][] paths, byte[] options, long token);
  public static native byte[] nativeCompare(byte[][] a, byte[][] b, byte[] options, long token);
  public static native int nativeCacheInvalidate(byte[] dir);
  public static native byte[] nativeVersion();
  public static native int nativeApiVersion();
}
