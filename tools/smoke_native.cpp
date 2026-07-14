#define WIN32_LEAN_AND_MEAN
#define NOMINMAX

#include <windows.h>

#include <algorithm>
#include <chrono>
#include <cstring>
#include <iostream>
#include <string>
#include <thread>
#include <vector>

using RVExtensionVersionFn = void(__stdcall*)(char* output, int outputSize);
using RVExtensionFn = void(__stdcall*)(char* output, int outputSize, const char* function);
namespace {

std::wstring Utf8ToWide(const std::string& value) {
    if (value.empty()) {
        return {};
    }

    const int required = MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, nullptr, 0);
    if (required <= 0) {
        return {};
    }

    std::wstring result(static_cast<std::size_t>(required), L'\0');
    if (MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, result.data(), required) != required) {
        return {};
    }
    result.pop_back();
    return result;
}

std::string Call(RVExtensionFn extension, const std::string& command) {
    std::vector<char> buffer(4096, '\0');
    extension(buffer.data(), static_cast<int>(buffer.size()), command.c_str());
    return std::string(buffer.data());
}

}  // namespace

int main(int argc, char** argv) {
    if (argc < 3) {
        std::cerr << "Usage: smoke_native.exe <extension_dir> <command> [<command> ...]\n";
        std::cerr << "Use sleep:<ms> between commands to wait.\n";
        return 1;
    }

    const std::wstring extensionDir = Utf8ToWide(argv[1]);
    if (extensionDir.empty() || !SetCurrentDirectoryW(extensionDir.c_str())) {
        std::cerr << "Failed to set current directory.\n";
        return 2;
    }

    const wchar_t* extensionDll =
#if defined(_WIN64)
        L"youtube_player_music_x64.dll";
#else
        L"youtube_player_music.dll";
#endif

    HMODULE module = LoadLibraryW(extensionDll);
    if (module == nullptr) {
        std::cerr << "LoadLibraryW failed: " << GetLastError() << "\n";
        return 3;
    }

    const auto version = reinterpret_cast<RVExtensionVersionFn>(GetProcAddress(module, "RVExtensionVersion"));
    const auto extension = reinterpret_cast<RVExtensionFn>(GetProcAddress(module, "RVExtension"));

    if (version == nullptr || extension == nullptr) {
        std::cerr << "Required exports not found.\n";
        FreeLibrary(module);
        return 4;
    }

    std::vector<char> versionBuffer(256, '\0');
    version(versionBuffer.data(), static_cast<int>(versionBuffer.size()));
    std::cout << "version => " << versionBuffer.data() << "\n";

    for (int index = 2; index < argc; ++index) {
        const std::string command = argv[index];

        if (command.rfind("sleep:", 0) == 0) {
            const int delayMs = std::max(0, std::atoi(command.c_str() + 6));
            std::cout << "sleep => " << delayMs << "ms\n";
            std::this_thread::sleep_for(std::chrono::milliseconds(delayMs));
            continue;
        }

        std::cout << command << " => " << Call(extension, command) << "\n";
    }

    FreeLibrary(module);
    return 0;
}
