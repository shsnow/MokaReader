// WizardJVMRunner — Apache License 2.0
//
// Creates the single in-process Java VM through the standard JNI Invocation
// API and forwards JSON requests to the Apache-licensed extension host
// (app.tachiaz.runtime.ExtensionHost.dispatch).

#include "include/WizardJVMBridge.h"
#include "WizardInternal.h"

#include <TargetConditionals.h>
#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

#include <os/log.h>

namespace {

os_log_t bridge_log() {
    static os_log_t value = os_log_create("cl.jonas.wizardcat", "jvm");
    return value;
}

// The VM writes its banner and fatal diagnostics through the vfprintf hook.
// The tail is kept so a failed boot can say why.
std::mutex output_mutex;
std::string recent_output;

void remember_output(const char *text) {
    std::lock_guard<std::mutex> lock(output_mutex);
    recent_output.append(text);
    if (recent_output.size() > 4096) {
        recent_output.erase(0, recent_output.size() - 4096);
    }
}

jint JNICALL hooked_vfprintf(FILE *, const char *format, va_list arguments) {
    char line[1024];
    va_list copy;
    va_copy(copy, arguments);
    int written = vsnprintf(line, sizeof(line), format, copy);
    va_end(copy);
    if (written > 0) {
        remember_output(line);
        os_log(bridge_log(), "[jvm] %{public}s", line);
    }
    return written;
}

void JNICALL hooked_exit(jint code) {
    os_log_error(bridge_log(), "[jvm] exit(%d) requested", code);
}

void JNICALL hooked_abort() {
    os_log_error(bridge_log(), "[jvm] abort requested");
}

char *duplicate(const std::string &value) {
    return strdup(value.c_str());
}

struct Runtime {
    JavaVM *vm = nullptr;
    jclass host_class = nullptr;
    jmethodID dispatch_method = nullptr;
};

/// The environment for the calling thread, attaching it if needed. Threads
/// stay attached: the app funnels every call through one serial queue.
JNIEnv *environment_for_current_thread(Runtime *runtime) {
    JNIEnv *environment = nullptr;
    jint status = runtime->vm->GetEnv(
        reinterpret_cast<void **>(&environment), JNI_VERSION_1_8
    );
    if (status == JNI_OK) {
        return environment;
    }
    if (status == JNI_EDETACHED) {
        JavaVMAttachArgs arguments{JNI_VERSION_1_8, const_cast<char *>("wizard-bridge"), nullptr};
        if (runtime->vm->AttachCurrentThread(
            reinterpret_cast<void **>(&environment), &arguments
        ) == JNI_OK) {
            return environment;
        }
    }
    return nullptr;
}

/// Describes and clears a pending Java exception.
std::string describe_exception(JNIEnv *environment) {
    jthrowable thrown = environment->ExceptionOccurred();
    if (thrown == nullptr) {
        return "Unknown Java exception";
    }
    environment->ExceptionClear();
    std::string message = "Java exception";
    jclass object_class = environment->FindClass("java/lang/Object");
    if (object_class != nullptr) {
        jmethodID to_string = environment->GetMethodID(
            object_class, "toString", "()Ljava/lang/String;"
        );
        if (to_string != nullptr) {
            auto text = static_cast<jstring>(
                environment->CallObjectMethod(thrown, to_string)
            );
            if (environment->ExceptionCheck()) {
                environment->ExceptionClear();
            } else if (text != nullptr) {
                message = wjb_std_string(environment, text);
                environment->DeleteLocalRef(text);
            }
        }
        environment->DeleteLocalRef(object_class);
    }
    environment->DeleteLocalRef(thrown);
    return message;
}

} // namespace

// MARK: - UTF helpers (shared with the natives)

std::string wjb_utf8_from_utf16(const jchar *characters, jsize length) {
    std::string result;
    result.reserve(static_cast<size_t>(length) * 3);
    for (jsize index = 0; index < length; ++index) {
        uint32_t code = characters[index];
        if (code >= 0xD800 && code <= 0xDBFF && index + 1 < length) {
            uint32_t low = characters[index + 1];
            if (low >= 0xDC00 && low <= 0xDFFF) {
                code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00);
                ++index;
            }
        }
        if (code < 0x80) {
            result.push_back(static_cast<char>(code));
        } else if (code < 0x800) {
            result.push_back(static_cast<char>(0xC0 | (code >> 6)));
            result.push_back(static_cast<char>(0x80 | (code & 0x3F)));
        } else if (code < 0x10000) {
            result.push_back(static_cast<char>(0xE0 | (code >> 12)));
            result.push_back(static_cast<char>(0x80 | ((code >> 6) & 0x3F)));
            result.push_back(static_cast<char>(0x80 | (code & 0x3F)));
        } else {
            result.push_back(static_cast<char>(0xF0 | (code >> 18)));
            result.push_back(static_cast<char>(0x80 | ((code >> 12) & 0x3F)));
            result.push_back(static_cast<char>(0x80 | ((code >> 6) & 0x3F)));
            result.push_back(static_cast<char>(0x80 | (code & 0x3F)));
        }
    }
    return result;
}

jstring wjb_java_string(JNIEnv *environment, const char *utf8) {
    if (utf8 == nullptr) {
        return nullptr;
    }
    // Decode UTF-8 into UTF-16 units; invalid bytes become U+FFFD.
    std::vector<jchar> units;
    const auto *bytes = reinterpret_cast<const unsigned char *>(utf8);
    size_t length = strlen(utf8);
    units.reserve(length);
    size_t index = 0;
    while (index < length) {
        uint32_t code = 0xFFFD;
        unsigned char first = bytes[index];
        size_t remaining = length - index;
        if (first < 0x80) {
            code = first;
            index += 1;
        } else if ((first >> 5) == 0x6 && remaining >= 2 &&
                   (bytes[index + 1] & 0xC0) == 0x80) {
            code = ((first & 0x1F) << 6) | (bytes[index + 1] & 0x3F);
            index += 2;
        } else if ((first >> 4) == 0xE && remaining >= 3 &&
                   (bytes[index + 1] & 0xC0) == 0x80 &&
                   (bytes[index + 2] & 0xC0) == 0x80) {
            code = ((first & 0x0F) << 12) |
                ((bytes[index + 1] & 0x3F) << 6) |
                (bytes[index + 2] & 0x3F);
            index += 3;
        } else if ((first >> 3) == 0x1E && remaining >= 4 &&
                   (bytes[index + 1] & 0xC0) == 0x80 &&
                   (bytes[index + 2] & 0xC0) == 0x80 &&
                   (bytes[index + 3] & 0xC0) == 0x80) {
            code = ((first & 0x07) << 18) |
                ((bytes[index + 1] & 0x3F) << 12) |
                ((bytes[index + 2] & 0x3F) << 6) |
                (bytes[index + 3] & 0x3F);
            index += 4;
        } else {
            index += 1;
        }
        if (code >= 0x10000) {
            code -= 0x10000;
            units.push_back(static_cast<jchar>(0xD800 + (code >> 10)));
            units.push_back(static_cast<jchar>(0xDC00 + (code & 0x3FF)));
        } else {
            units.push_back(static_cast<jchar>(code));
        }
    }
    return environment->NewString(units.data(), static_cast<jsize>(units.size()));
}

std::string wjb_std_string(JNIEnv *environment, jstring value) {
    if (value == nullptr) {
        return "";
    }
    jsize length = environment->GetStringLength(value);
    const jchar *characters = environment->GetStringChars(value, nullptr);
    if (characters == nullptr) {
        return "";
    }
    std::string result = wjb_utf8_from_utf16(characters, length);
    environment->ReleaseStringChars(value, characters);
    return result;
}

// MARK: - Public API

extern "C" WJBRuntime *wjb_runtime_create(
    const char *java_home,
    const char *frameworks_directory,
    const char *classpath,
    const char *const *additional_options,
    int additional_option_count,
    char **error_message
) {
    if (error_message != nullptr) {
        *error_message = nullptr;
    }
    if (java_home == nullptr || frameworks_directory == nullptr ||
        classpath == nullptr || additional_option_count < 0) {
        if (error_message != nullptr) {
            *error_message = duplicate("Invalid VM configuration arguments");
        }
        return nullptr;
    }

    setenv("JAVA_HOME", java_home, 1);

    std::vector<std::string> option_values = {
        std::string("-Djava.home=") + java_home,
        std::string("-Djava.class.path=") + classpath,
        std::string("-Djava.library.path=") + frameworks_directory,
        "-Djava.awt.headless=true",
        // iOS owns every signal; the VM must not install handlers.
        "-Xrs",
        "-Xms16m",
        "-Xmx128m",
        "-Xss512k",
#if TARGET_OS_IPHONE
        // The default 1 GiB compressed-class reservation is refused by iOS.
        "-XX:CompressedClassSpaceSize=64m",
        "-XX:InitialCodeCacheSize=4m",
        "-XX:ReservedCodeCacheSize=32m",
        "-XX:+DisplayVMOutputToStderr",
#endif
    };
    for (int index = 0; index < additional_option_count; ++index) {
        if (additional_options != nullptr && additional_options[index] != nullptr) {
            option_values.emplace_back(additional_options[index]);
        }
    }

    std::vector<JavaVMOption> options;
    options.reserve(option_values.size() + 3);
    for (auto &value : option_values) {
        options.push_back({const_cast<char *>(value.c_str()), nullptr});
    }
    options.push_back({
        const_cast<char *>("vfprintf"),
        reinterpret_cast<void *>(&hooked_vfprintf)
    });
    options.push_back({
        const_cast<char *>("exit"),
        reinterpret_cast<void *>(&hooked_exit)
    });
    options.push_back({
        const_cast<char *>("abort"),
        reinterpret_cast<void *>(&hooked_abort)
    });

    JavaVMInitArgs arguments{};
    arguments.version = JNI_VERSION_1_8;
    arguments.nOptions = static_cast<jint>(options.size());
    arguments.options = options.data();
    arguments.ignoreUnrecognized = JNI_TRUE;

    {
        std::lock_guard<std::mutex> lock(output_mutex);
        recent_output.clear();
    }

    JavaVM *vm = nullptr;
    JNIEnv *environment = nullptr;
    jint created = JNI_CreateJavaVM(
        &vm, reinterpret_cast<void **>(&environment), &arguments
    );
    if (created != JNI_OK || vm == nullptr || environment == nullptr) {
        if (error_message != nullptr) {
            std::string tail;
            {
                std::lock_guard<std::mutex> lock(output_mutex);
                tail = recent_output;
            }
            *error_message = duplicate(
                "JNI_CreateJavaVM failed with code " + std::to_string(created) +
                (tail.empty() ? "" : ("\n" + tail))
            );
        }
        return nullptr;
    }

    auto *runtime = new Runtime();
    runtime->vm = vm;

    std::string failure;
    jclass local_host = environment->FindClass("app/tachiaz/runtime/ExtensionHost");
    if (local_host == nullptr) {
        environment->ExceptionClear();
        failure = "Extension host class is missing from the classpath";
    } else {
        runtime->host_class = static_cast<jclass>(environment->NewGlobalRef(local_host));
        environment->DeleteLocalRef(local_host);
        runtime->dispatch_method = environment->GetStaticMethodID(
            runtime->host_class, "dispatch", "(Ljava/lang/String;)Ljava/lang/String;"
        );
        if (runtime->dispatch_method == nullptr) {
            environment->ExceptionClear();
            failure = "Extension host dispatch method is missing";
        }
    }

    if (failure.empty() && !wjb_register_natives(environment, failure)) {
        // failure describes the problem.
    }

    if (!failure.empty()) {
        if (error_message != nullptr) {
            *error_message = duplicate(failure);
        }
        if (runtime->host_class != nullptr) {
            environment->DeleteGlobalRef(runtime->host_class);
        }
        delete runtime;
        // The VM cannot be destroyed safely; the next attempt would fail to
        // create a second one, which the Swift layer surfaces as an error.
        return nullptr;
    }

    return reinterpret_cast<WJBRuntime *>(runtime);
}

extern "C" WJBStatus wjb_runtime_dispatch(
    WJBRuntime *opaque,
    const char *request_json,
    char **response_json,
    char **error_message
) {
    if (response_json != nullptr) {
        *response_json = nullptr;
    }
    if (error_message != nullptr) {
        *error_message = nullptr;
    }
    auto *runtime = reinterpret_cast<Runtime *>(opaque);
    if (runtime == nullptr || request_json == nullptr || response_json == nullptr) {
        return WJBStatusInvalidArgument;
    }

    JNIEnv *environment = environment_for_current_thread(runtime);
    if (environment == nullptr) {
        if (error_message != nullptr) {
            *error_message = duplicate("Unable to attach thread to the VM");
        }
        return WJBStatusThreadAttachFailed;
    }

    jstring request = wjb_java_string(environment, request_json);
    if (request == nullptr) {
        if (error_message != nullptr) {
            *error_message = duplicate("Unable to allocate the request string");
        }
        return WJBStatusAllocationFailed;
    }

    auto response = static_cast<jstring>(environment->CallStaticObjectMethod(
        runtime->host_class, runtime->dispatch_method, request
    ));
    environment->DeleteLocalRef(request);

    if (environment->ExceptionCheck()) {
        std::string message = describe_exception(environment);
        if (response != nullptr) {
            environment->DeleteLocalRef(response);
        }
        if (error_message != nullptr) {
            *error_message = duplicate(message);
        }
        return WJBStatusJavaException;
    }

    if (response == nullptr) {
        if (error_message != nullptr) {
            *error_message = duplicate("The extension host returned no response");
        }
        return WJBStatusJavaException;
    }

    std::string text = wjb_std_string(environment, response);
    environment->DeleteLocalRef(response);
    *response_json = duplicate(text);
    if (*response_json == nullptr) {
        return WJBStatusAllocationFailed;
    }
    return WJBStatusOK;
}

extern "C" void wjb_runtime_release(WJBRuntime *opaque) {
    auto *runtime = reinterpret_cast<Runtime *>(opaque);
    if (runtime == nullptr) {
        return;
    }
    // Global refs are deliberately kept: the VM outlives every handle, and
    // the app only ever creates one runtime per process.
    delete runtime;
}

extern "C" void wjb_string_free(char *value) {
    std::free(value);
}
