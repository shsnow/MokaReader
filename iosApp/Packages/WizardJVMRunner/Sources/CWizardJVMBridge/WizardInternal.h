// WizardJVMRunner — Apache License 2.0
// Target-internal declarations shared between the VM bridge and the natives.

#ifndef WizardInternal_h
#define WizardInternal_h

#include "include/jni.h"

#include <string>

/// Registers the app.tachiaz.compat.NativeBridge methods. On failure returns
/// false and describes the problem in error.
bool wjb_register_natives(JNIEnv *environment, std::string &error);

/// UTF-16 (JNI jchar) to UTF-8, surrogate pairs included.
std::string wjb_utf8_from_utf16(const jchar *characters, jsize length);

/// Builds a Java string from real UTF-8 (not modified UTF-8), so titles with
/// emoji and other non-BMP characters survive the crossing.
jstring wjb_java_string(JNIEnv *environment, const char *utf8);

/// Reads a Java string as real UTF-8. Returns an empty string for null.
std::string wjb_std_string(JNIEnv *environment, jstring value);

#endif
