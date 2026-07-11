#pragma once

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX

#include <windows.h>

#include <algorithm>
#include <cctype>
#include <cstring>
#include <limits>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace a3yt {

inline void WriteOutput(char* output, int outputSize, std::string_view value) noexcept {
    if (output == nullptr || outputSize <= 0) {
        return;
    }

    const auto capacity = static_cast<std::size_t>(outputSize - 1);
    const auto copyLength = std::min(value.size(), capacity);
    if (copyLength != 0) {
        std::memcpy(output, value.data(), copyLength);
    }
    output[copyLength] = '\0';
}

inline std::string Trim(std::string value) {
    constexpr std::string_view whitespace = " \t\r\n";
    const auto first = value.find_first_not_of(whitespace);
    if (first == std::string::npos) {
        return {};
    }

    const auto last = value.find_last_not_of(whitespace);
    return value.substr(first, last - first + 1);
}

inline std::string StripWrappingQuotes(std::string value) {
    value = Trim(std::move(value));
    if (value.size() >= 2 && value.front() == '"' && value.back() == '"') {
        value = value.substr(1, value.size() - 2);
    }
    return value;
}

inline std::string ToLowerAscii(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char ch) {
        return static_cast<char>(std::tolower(ch));
    });
    return value;
}

inline std::string SanitizeProtocolField(std::string value) {
    for (char& ch : value) {
        if (ch == '\r' || ch == '\n' || ch == '|') {
            ch = ' ';
        }
    }
    return value;
}

inline std::vector<std::string> Split(std::string_view value, char separator) {
    std::vector<std::string> parts;
    std::size_t offset = 0;
    while (offset <= value.size()) {
        const auto next = value.find(separator, offset);
        if (next == std::string_view::npos) {
            parts.emplace_back(value.substr(offset));
            break;
        }

        parts.emplace_back(value.substr(offset, next - offset));
        offset = next + 1;
    }
    return parts;
}

inline std::wstring Utf8ToWide(std::string_view value) {
    if (value.empty() || value.size() > static_cast<std::size_t>(std::numeric_limits<int>::max())) {
        return {};
    }

    const int valueSize = static_cast<int>(value.size());
    const int required = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(), valueSize, nullptr, 0);
    if (required <= 0) {
        return {};
    }

    std::wstring result(static_cast<std::size_t>(required), L'\0');
    if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(), valueSize, result.data(), required) != required) {
        return {};
    }
    return result;
}

inline std::string WideToUtf8(std::wstring_view value) {
    if (value.empty() || value.size() > static_cast<std::size_t>(std::numeric_limits<int>::max())) {
        return {};
    }

    const int valueSize = static_cast<int>(value.size());
    const int required = WideCharToMultiByte(
        CP_UTF8, WC_ERR_INVALID_CHARS, value.data(), valueSize, nullptr, 0, nullptr, nullptr);
    if (required <= 0) {
        return {};
    }

    std::string result(static_cast<std::size_t>(required), '\0');
    if (WideCharToMultiByte(
            CP_UTF8, WC_ERR_INVALID_CHARS, value.data(), valueSize, result.data(), required, nullptr, nullptr) != required) {
        return {};
    }
    return result;
}

}  // namespace a3yt
