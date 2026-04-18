#define WIN32_LEAN_AND_MEAN
#define NOMINMAX

#include <windows.h>

#include <algorithm>
#include <cctype>
#include <cstring>
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

void WriteOutput(char* output, int outputSize, const std::string& value) {
    if (output == nullptr || outputSize <= 0) {
        return;
    }

    const int maxChars = outputSize - 1;
    const int copyLength = static_cast<int>(std::min<std::size_t>(value.size(), static_cast<std::size_t>(maxChars)));
    if (copyLength > 0) {
        std::memcpy(output, value.data(), static_cast<std::size_t>(copyLength));
    }

    output[copyLength] = '\0';
}

std::string Sanitize(std::string value) {
    for (char& ch : value) {
        if (ch == '\r' || ch == '\n' || ch == '|') {
            ch = ' ';
        }
    }

    return value;
}

std::string ToLowerAscii(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char ch) {
        return static_cast<char>(std::tolower(ch));
    });
    return value;
}

std::vector<std::string> SplitCommand(const std::string& value) {
    std::vector<std::string> parts;
    std::size_t offset = 0;

    while (offset <= value.size()) {
        const std::size_t next = value.find('|', offset);
        if (next == std::string::npos) {
            parts.push_back(value.substr(offset));
            break;
        }

        parts.push_back(value.substr(offset, next - offset));
        offset = next + 1;
    }

    return parts;
}

std::string HandleCommand(const std::string& rawCommand) {
    if (rawCommand.empty()) {
        return "err|missing_argument|command";
    }

    const std::vector<std::string> parts = SplitCommand(rawCommand);
    const std::string command = ToLowerAscii(parts.empty() ? std::string{} : parts.front());

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
        const std::string title = parts.size() > 1 ? Sanitize(parts[1]) : std::string{};
        return "ok|title|" + title;
    }

    if (command == "playlistload" || command == "playlistitem" || command == "seek") {
        return kUnsupported;
    }

    if (command == "play") {
        return kUnsupported;
    }

    return "err|unknown_command|" + Sanitize(command);
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
    WriteOutput(output, outputSize, kVersion);
}

__declspec(dllexport) void __stdcall RVExtension(char* output, int outputSize, const char* function) {
    WriteOutput(output, outputSize, HandleCommand(function != nullptr ? function : ""));
}

__declspec(dllexport) int __stdcall RVExtensionArgs(char* output, int outputSize, const char* function, const char** args, int argCount) {
    WriteOutput(output, outputSize, HandleArgs(function != nullptr ? function : "", args, argCount));
    return 0;
}

}  // extern "C"
