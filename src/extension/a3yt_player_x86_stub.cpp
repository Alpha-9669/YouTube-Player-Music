#include "extension_common.hpp"

#include <string>
#include <vector>

#if !defined(_WIN64)
#pragma comment(linker, "/EXPORT:RVExtension=_RVExtension@12")
#pragma comment(linker, "/EXPORT:RVExtensionArgs=_RVExtensionArgs@20")
#pragma comment(linker, "/EXPORT:RVExtensionVersion=_RVExtensionVersion@8")
#endif

namespace {

constexpr char kVersion[] = "A3YTPlayer 0.7.0 x86-compat";
constexpr char kUnsupported[] = "err|unsupported|x86_client_not_supported_use_x64";

std::string HandleCommand(const std::string& rawCommand) {
    if (rawCommand.empty()) {
        return "err|missing_argument|command";
    }

    const std::vector<std::string> parts = a3yt::Split(rawCommand, '|');
    const std::string command = a3yt::ToLowerAscii(parts.empty() ? std::string{} : parts.front());

    if (command == "version") {
        return std::string("ok|version|") + kVersion;
    }

    if (command == "status") {
        return "ok|status|idle";
    }

    if (command == "timeline") {
        return "ok|timeline|idle|0|0";
    }

    if (command == "warmup") {
        return "ok|warmup";
    }

    if (command == "stop") {
        return "ok|stopped";
    }

    if (command == "pause") {
        return "ok|paused";
    }

    if (command == "resume") {
        return "ok|status|idle";
    }

    if (command == "prefetch") {
        return "ok|prefetched";
    }

    if (command == "title") {
        const std::string title = parts.size() > 1 ? a3yt::SanitizeProtocolField(parts[1]) : std::string{};
        return "ok|title|" + title;
    }

    if (command == "playlistload" || command == "playlistitem" || command == "seek") {
        return kUnsupported;
    }

    if (command == "play") {
        return kUnsupported;
    }

    return "err|unknown_command|" + a3yt::SanitizeProtocolField(command);
}

std::string HandleArgs(const std::string& function, const char** args, int argCount) {
    std::string command = function;
    for (int index = 0; index < argCount; ++index) {
        command += "|";
        if (args != nullptr && args[index] != nullptr) {
            command += args[index];
        }
    }

    return HandleCommand(command);
}

}  // namespace

extern "C" {

__declspec(dllexport) void __stdcall RVExtensionVersion(char* output, int outputSize) {
    a3yt::WriteOutput(output, outputSize, kVersion);
}

__declspec(dllexport) void __stdcall RVExtension(char* output, int outputSize, const char* function) {
    try {
        a3yt::WriteOutput(output, outputSize, HandleCommand(function != nullptr ? function : ""));
    } catch (...) {
        a3yt::WriteOutput(output, outputSize, "err|internal|exception");
    }
}

__declspec(dllexport) int __stdcall RVExtensionArgs(char* output, int outputSize, const char* function, const char** args, int argCount) {
    try {
        a3yt::WriteOutput(output, outputSize, HandleArgs(function != nullptr ? function : "", args, argCount));
        return 0;
    } catch (...) {
        a3yt::WriteOutput(output, outputSize, "err|internal|exception");
        return 4;
    }
}

}  // extern "C"
