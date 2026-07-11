#include "extension_common.hpp"

#include <mfapi.h>
#include <mfidl.h>
#include <mfplay.h>
#include <propidl.h>
#include <propsys.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <limits>
#include <mutex>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

namespace {

constexpr char kVersion[] = "A3YTPlayer 0.7.0";
constexpr char kPlaylistMetaSeparator = '\x1D';
constexpr char kPlaylistRecordSeparator = '\x1E';
constexpr char kPlaylistFieldSeparator = '\x1F';
constexpr char kForceRefreshPrefix[] = "a3yt-refresh:";
constexpr std::int64_t kHundredNsPerMillisecond = 10000;
constexpr std::int64_t kMaxPositionMs = std::numeric_limits<std::int64_t>::max() / kHundredNsPerMillisecond;
using ResolveAudioStreamFn = int(__stdcall*)(const char* input, char* output, int outputSize);
using ResolveTrackTitleFn = int(__stdcall*)(const char* input, char* output, int outputSize);
using WarmupBackendFn = int(__stdcall*)(char* output, int outputSize);
using ResolvePlaylistFn = int(__stdcall*)(const char* input, char* output, int outputSize);

extern "C" {
int __stdcall YPM0(const char* input, char* output, int outputSize);
int __stdcall YPM1(const char* input, char* output, int outputSize);
int __stdcall YPM2(char* output, int outputSize);
int __stdcall YPM3(const char* input, char* output, int outputSize);
}

enum class PlayerState {
    Playing,
    Paused,
    Stopped,
    Error,
};

struct PlayerHandle {
    IMFPMediaPlayer* player = nullptr;
    IMFPMediaItem* mediaItem = nullptr;
    std::string sourceUrl;
    std::string lastError;
};

enum class PlaybackStage {
    Idle,
    Resolving,
    Playing,
    Paused,
    Error,
};

struct PlaylistEntry {
    std::string url;
    std::string title;
};

std::mutex g_mutex;
std::condition_variable g_commandCv;
std::condition_variable g_prefetchCv;
bool g_workerStarted = false;
bool g_shutdownRequested = false;
std::uint64_t g_commandSerial = 0;
bool g_commandIsPlay = false;
std::string g_commandUrl;
int g_commandVolume = 70;
std::atomic<int> g_pendingVolume{-1};
std::uint64_t g_prefetchSerial = 0;
bool g_prefetchRunning = false;
std::string g_prefetchUrl;
std::wstring g_prefetchResolvedUrl;
std::string g_prefetchError;
bool g_warmupRequested = false;
bool g_warmupCompleted = false;
bool g_pauseRequested = false;
PlaybackStage g_stage = PlaybackStage::Idle;
std::string g_lastError;
std::uint64_t g_playlistToken = 0;
std::vector<PlaylistEntry> g_playlistItems;
std::string g_playlistTitle;
std::atomic<long long> g_timelinePositionMs{0};
std::atomic<long long> g_timelineDurationMs{0};
std::atomic<long long> g_pendingSeekMs{-1};
std::atomic<bool> g_debugEnabled{false};
std::mutex g_debugLogMutex;

std::string HResultMessage(const char* prefix, HRESULT hr);
void DebugLog(const std::string& message) noexcept;

struct PlaybackBackendThreadState {
    bool initialized = false;
    bool mediaFoundationStarted = false;
    HRESULT coInitializeHr = E_FAIL;
};

PlaybackBackendThreadState& GetPlaybackBackendThreadState() {
    static thread_local PlaybackBackendThreadState state{};
    return state;
}

bool EnsurePlaybackBackendReady(std::string* errorMessage = nullptr) {
    auto& state = GetPlaybackBackendThreadState();
    if (state.initialized) {
        return true;
    }

    state.coInitializeHr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    if (FAILED(state.coInitializeHr) && state.coInitializeHr != RPC_E_CHANGED_MODE) {
        if (errorMessage != nullptr) {
            *errorMessage = HResultMessage("coinitialize", state.coInitializeHr);
        }
        return false;
    }

    const HRESULT startupHr = MFStartup(MF_VERSION);
    if (FAILED(startupHr)) {
        if (errorMessage != nullptr) {
            *errorMessage = HResultMessage("mfstartup", startupHr);
        }
        if (state.coInitializeHr == S_OK || state.coInitializeHr == S_FALSE) {
            CoUninitialize();
        }
        state = {};
        return false;
    }

    state.mediaFoundationStarted = true;
    state.initialized = true;
    DebugLog("mfplay|ready");
    return true;
}

void ShutdownPlaybackBackendThread() {
    auto& state = GetPlaybackBackendThreadState();
    if (!state.initialized) {
        return;
    }

    if (state.mediaFoundationStarted) {
        MFShutdown();
    }

    if (state.coInitializeHr == S_OK || state.coInitializeHr == S_FALSE) {
        CoUninitialize();
    }

    state = {};
}

void WriteOutput(char* output, int outputSize, const std::string& value) {
    a3yt::WriteOutput(output, outputSize, value);
}

std::wstring Utf8ToWide(const std::string& value) {
    return a3yt::Utf8ToWide(value);
}

std::string WideToUtf8(const std::wstring& value) {
    return a3yt::WideToUtf8(value);
}

std::string Sanitize(const std::string& value) {
    return a3yt::SanitizeProtocolField(value);
}

std::filesystem::path GetDebugLogPath() {
    wchar_t* localAppData = nullptr;
    std::size_t required = 0;
    _wdupenv_s(&localAppData, &required, L"LOCALAPPDATA");
    std::filesystem::path path;
    if (localAppData != nullptr && required > 0) {
        path = std::filesystem::path(localAppData) / L"Arma 3" / L"A3YT_extension.log";
        free(localAppData);
    } else {
        path = std::filesystem::temp_directory_path() / L"A3YT_extension.log";
    }
    return path;
}

void DebugLog(const std::string& message) noexcept {
    if (!g_debugEnabled.load()) {
        return;
    }

    try {
        SYSTEMTIME localTime{};
        GetLocalTime(&localTime);

        char timestamp[64]{};
        std::snprintf(
            timestamp,
            sizeof(timestamp),
            "%04u-%02u-%02u %02u:%02u:%02u.%03u",
            static_cast<unsigned>(localTime.wYear),
            static_cast<unsigned>(localTime.wMonth),
            static_cast<unsigned>(localTime.wDay),
            static_cast<unsigned>(localTime.wHour),
            static_cast<unsigned>(localTime.wMinute),
            static_cast<unsigned>(localTime.wSecond),
            static_cast<unsigned>(localTime.wMilliseconds));

        std::lock_guard<std::mutex> lock(g_debugLogMutex);
        const std::filesystem::path logPath = GetDebugLogPath();
        std::error_code error;
        std::filesystem::create_directories(logPath.parent_path(), error);

        std::ofstream logStream(logPath, std::ios::app | std::ios::binary);
        if (logStream.is_open()) {
            logStream << "[" << timestamp << "]"
                      << "[tid=" << GetCurrentThreadId() << "] "
                      << message << "\r\n";
        }
    } catch (...) {
        // Diagnostics must never terminate the playback worker or escape an ABI export.
    }
}

bool PinCurrentModule() noexcept {
    static std::once_flag once;
    static bool pinned = false;
    try {
        std::call_once(once, []() {
            HMODULE module = nullptr;
            pinned = GetModuleHandleExW(
                GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN,
                reinterpret_cast<LPCWSTR>(&PinCurrentModule),
                &module) != FALSE;
        });
    } catch (...) {
        return false;
    }
    return pinned;
}

bool TryParseBoolLoose(const std::string& rawValue, bool* result) {
    if (result == nullptr) {
        return false;
    }

    std::string value = a3yt::Trim(rawValue);
    if (value.size() >= 2 && value.front() == '"' && value.back() == '"') {
        value = value.substr(1, value.size() - 2);
    }
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char ch) {
        return static_cast<char>(std::tolower(ch));
    });

    if (value == "1" || value == "true" || value == "on" || value == "yes") {
        *result = true;
        return true;
    }

    if (value == "0" || value == "false" || value == "off" || value == "no") {
        *result = false;
        return true;
    }

    return false;
}

std::string TrimWhitespace(std::string value) {
    return a3yt::Trim(std::move(value));
}

std::string StripWrappingQuotes(std::string value) {
    return a3yt::StripWrappingQuotes(std::move(value));
}

bool TryParseInt64Loose(const std::string& rawValue, std::int64_t* result) {
    if (result == nullptr) {
        return false;
    }

    const std::string value = StripWrappingQuotes(rawValue);
    if (value.empty()) {
        return false;
    }

    try {
        std::size_t consumed = 0;
        const long long parsed = std::stoll(value, &consumed, 10);
        if (consumed == value.size()) {
            *result = static_cast<std::int64_t>(parsed);
            return true;
        }
    } catch (...) {
    }

    try {
        std::size_t consumed = 0;
        const long double parsed = std::stold(value, &consumed);
        if (consumed != value.size() || !std::isfinite(static_cast<double>(parsed))) {
            return false;
        }

        if (parsed >= static_cast<long double>(std::numeric_limits<std::int64_t>::max())) {
            *result = std::numeric_limits<std::int64_t>::max();
        } else if (parsed <= static_cast<long double>(std::numeric_limits<std::int64_t>::min())) {
            *result = std::numeric_limits<std::int64_t>::min();
        } else {
            *result = static_cast<std::int64_t>(std::llround(parsed));
        }
        return true;
    } catch (...) {
    }

    return false;
}

std::vector<std::string> SplitByChar(const std::string& value, char separator) {
    return a3yt::Split(value, separator);
}

std::string GetStageName(PlaybackStage stage) {
    switch (stage) {
        case PlaybackStage::Idle:
            return "idle";
        case PlaybackStage::Resolving:
            return "resolving";
        case PlaybackStage::Playing:
            return "playing";
        case PlaybackStage::Paused:
            return "paused";
        case PlaybackStage::Error:
            return "error";
    }

    return "unknown";
}

std::string HResultMessage(const char* prefix, HRESULT hr) {
    LPWSTR raw = nullptr;
    const DWORD flags = FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS;
    const DWORD length = FormatMessageW(flags, nullptr, static_cast<DWORD>(hr), 0, reinterpret_cast<LPWSTR>(&raw), 0, nullptr);

    if (length == 0 || raw == nullptr) {
        char code[11]{};
        std::snprintf(code, sizeof(code), "0x%08lX", static_cast<unsigned long>(hr));
        return std::string(prefix) + "|" + code;
    }

    std::wstring message(raw, static_cast<std::size_t>(length));
    LocalFree(raw);
    return std::string(prefix) + "|" + Sanitize(WideToUtf8(message));
}

bool TryReadPropVariantInt64(const PROPVARIANT& value, std::int64_t* result) {
    if (result == nullptr) {
        return false;
    }

    switch (value.vt) {
        case VT_I8:
            *result = value.hVal.QuadPart;
            return true;
        case VT_UI8:
            *result = value.uhVal.QuadPart > static_cast<ULONGLONG>(std::numeric_limits<std::int64_t>::max())
                ? std::numeric_limits<std::int64_t>::max()
                : static_cast<std::int64_t>(value.uhVal.QuadPart);
            return true;
        case VT_I4:
            *result = value.lVal;
            return true;
        case VT_UI4:
            *result = value.ulVal;
            return true;
        case VT_EMPTY:
            *result = 0;
            return true;
        default:
            return false;
    }
}

void ResetTimelineState() {
    g_timelinePositionMs.store(0);
    g_timelineDurationMs.store(0);
}

void ClearPendingSeekState() {
    g_pendingSeekMs.store(-1);
}

void ClearPendingVolumeState() {
    g_pendingVolume.store(-1);
}

std::int64_t ClampPositionMs(std::int64_t value) {
    return std::clamp<std::int64_t>(value, 0, kMaxPositionMs);
}

bool TryParseUInt64Strict(const std::string& rawValue, std::uint64_t* result) {
    if (result == nullptr) {
        return false;
    }

    const std::string value = StripWrappingQuotes(rawValue);
    if (value.empty() || value.front() == '-') {
        return false;
    }

    try {
        std::size_t consumed = 0;
        const auto parsed = std::stoull(value, &consumed, 10);
        if (consumed != value.size()) {
            return false;
        }
        *result = static_cast<std::uint64_t>(parsed);
        return true;
    } catch (...) {
        return false;
    }
}

bool TryParseIntStrict(const std::string& rawValue, int* result) {
    if (result == nullptr) {
        return false;
    }

    const std::string value = StripWrappingQuotes(rawValue);
    try {
        std::size_t consumed = 0;
        const long long parsed = std::stoll(value, &consumed, 10);
        if (consumed != value.size() || parsed < std::numeric_limits<int>::min() || parsed > std::numeric_limits<int>::max()) {
            return false;
        }
        *result = static_cast<int>(parsed);
        return true;
    } catch (...) {
        return false;
    }
}

class PlayerCallback final : public IMFPMediaPlayerCallback {
public:
    STDMETHODIMP QueryInterface(REFIID riid, void** ppvObject) override {
        if (ppvObject == nullptr) {
            return E_POINTER;
        }

        *ppvObject = nullptr;
        if (riid == __uuidof(IUnknown) || riid == __uuidof(IMFPMediaPlayerCallback)) {
            *ppvObject = static_cast<IMFPMediaPlayerCallback*>(this);
            AddRef();
            return S_OK;
        }

        return E_NOINTERFACE;
    }

    STDMETHODIMP_(ULONG) AddRef() override {
        return ++referenceCount_;
    }

    STDMETHODIMP_(ULONG) Release() override {
        const ULONG value = --referenceCount_;
        if (value == 0) {
            delete this;
        }
        return value;
    }

    void STDMETHODCALLTYPE OnMediaPlayerEvent(MFP_EVENT_HEADER* eventHeader) override {
        if (eventHeader == nullptr) {
            return;
        }

        if (FAILED(eventHeader->hrEvent)) {
            MarkError(HResultMessage("mfplay", eventHeader->hrEvent), eventHeader->hrEvent);
        }

        switch (eventHeader->eEventType) {
            case MFP_EVENT_TYPE_PLAY:
                if (MarkPlay()) {
                    DebugLog("mfplay_event|play");
                }
                break;
            case MFP_EVENT_TYPE_PAUSE:
                DebugLog("mfplay_event|pause");
                break;
            case MFP_EVENT_TYPE_STOP:
                DebugLog("mfplay_event|stop");
                break;
            case MFP_EVENT_TYPE_POSITION_SET:
                DebugLog("mfplay_event|position_set");
                break;
            case MFP_EVENT_TYPE_PLAYBACK_ENDED:
                if (MarkEnded()) {
                    DebugLog("mfplay_event|ended");
                }
                break;
            case MFP_EVENT_TYPE_ERROR:
                if (MarkError(HResultMessage("mfplay", eventHeader->hrEvent), eventHeader->hrEvent)) {
                    DebugLog("mfplay_event|error|" + HResultMessage("mfplay", eventHeader->hrEvent));
                }
                break;
            default:
                break;
        }

    }

    bool MarkPlay() {
        bool expected = false;
        if (sawPlay_.compare_exchange_strong(expected, true)) {
            return true;
        }
        return false;
    }

    bool MarkEnded() {
        bool expected = false;
        if (playbackEnded_.compare_exchange_strong(expected, true)) {
            return true;
        }
        return false;
    }

    bool MarkError(const std::string& message, HRESULT errorCode = E_FAIL) {
        lastError_.store(errorCode);
        {
            std::lock_guard<std::mutex> lock(errorMutex_);
            lastErrorMessage_ = Sanitize(message);
        }

        bool expected = false;
        if (sawError_.compare_exchange_strong(expected, true)) {
            return true;
        }
        return false;
    }

    bool SawPlay() const {
        return sawPlay_.load();
    }

    bool PlaybackEnded() const {
        return playbackEnded_.load();
    }

    bool SawError() const {
        return sawError_.load();
    }

    HRESULT LastError() const {
        return lastError_.load();
    }

    std::string LastErrorMessage() const {
        std::lock_guard<std::mutex> lock(errorMutex_);
        return lastErrorMessage_;
    }

    void Reset() {
        sawPlay_.store(false);
        playbackEnded_.store(false);
        sawError_.store(false);
        lastError_.store(S_OK);
        std::lock_guard<std::mutex> lock(errorMutex_);
        lastErrorMessage_.clear();
    }

private:
    std::atomic<ULONG> referenceCount_{1};
    std::atomic<bool> sawPlay_{false};
    std::atomic<bool> playbackEnded_{false};
    std::atomic<bool> sawError_{false};
    std::atomic<HRESULT> lastError_{S_OK};
    mutable std::mutex errorMutex_;
    std::string lastErrorMessage_;
};

PlayerState GetPlayerState(PlayerHandle* player) {
    if (player == nullptr || player->player == nullptr) {
        return PlayerState::Stopped;
    }

    MFP_MEDIAPLAYER_STATE state = MFP_MEDIAPLAYER_STATE_EMPTY;
    const HRESULT hr = player->player->GetState(&state);
    if (FAILED(hr)) {
        player->lastError = HResultMessage("mfplay", hr);
        return PlayerState::Error;
    }

    switch (state) {
        case MFP_MEDIAPLAYER_STATE_PLAYING:
            return PlayerState::Playing;
        case MFP_MEDIAPLAYER_STATE_PAUSED:
            return PlayerState::Paused;
        case MFP_MEDIAPLAYER_STATE_STOPPED:
        case MFP_MEDIAPLAYER_STATE_EMPTY:
            return PlayerState::Stopped;
        case MFP_MEDIAPLAYER_STATE_SHUTDOWN:
            return PlayerState::Error;
    }

    return PlayerState::Stopped;
}

std::string GetPlayerLastError(PlayerHandle* player) {
    if (player == nullptr || player->lastError.empty()) {
        return "mfplay|state_error";
    }

    return player->lastError;
}

void UpdateCallbackFromPlayer(PlayerHandle* player, PlayerCallback* callback) {
    if (player == nullptr || callback == nullptr) {
        return;
    }

    const PlayerState state = GetPlayerState(player);
    switch (state) {
        case PlayerState::Playing:
            if (callback->MarkPlay()) {
                DebugLog("mfplay_poll|play");
            }
            break;
        case PlayerState::Error:
            if (callback->MarkError(GetPlayerLastError(player))) {
                DebugLog("mfplay_poll|error|" + GetPlayerLastError(player));
            }
            break;
        default:
            break;
    }
}

bool PausePlayer(PlayerHandle* player, std::string* errorMessage = nullptr) {
    if (player == nullptr || player->player == nullptr) {
        if (errorMessage != nullptr) {
            *errorMessage = "mfplay|pause_unavailable";
        }
        return false;
    }

    const HRESULT hr = player->player->Pause();
    if (FAILED(hr)) {
        player->lastError = HResultMessage("mfplay_pause", hr);
        if (errorMessage != nullptr) {
            *errorMessage = player->lastError;
        }
        return false;
    }

    return true;
}

bool PlayPlayer(PlayerHandle* player, std::string* errorMessage = nullptr) {
    if (player == nullptr || player->player == nullptr) {
        if (errorMessage != nullptr) {
            *errorMessage = "mfplay|play_unavailable";
        }
        return false;
    }

    const HRESULT hr = player->player->Play();
    if (FAILED(hr)) {
        player->lastError = HResultMessage("mfplay_play", hr);
        if (errorMessage != nullptr) {
            *errorMessage = player->lastError;
        }
        return false;
    }

    return true;
}

bool SetPlayerPositionMs(PlayerHandle* player, std::int64_t requestedMs, std::string* errorMessage = nullptr) {
    if (player == nullptr || player->player == nullptr) {
        if (errorMessage != nullptr) {
            *errorMessage = "mfplay|seek_unavailable";
        }
        return false;
    }

    PROPVARIANT value{};
    PropVariantInit(&value);
    value.vt = VT_I8;
    value.hVal.QuadPart = ClampPositionMs(requestedMs) * kHundredNsPerMillisecond;

    const HRESULT hr = player->player->SetPosition(MFP_POSITIONTYPE_100NS, &value);
    PropVariantClear(&value);
    if (FAILED(hr)) {
        player->lastError = HResultMessage("mfplay_seek", hr);
        if (errorMessage != nullptr) {
            *errorMessage = player->lastError;
        }
        return false;
    }

    return true;
}

void StopAndReleasePlayer(PlayerHandle*& player) {
    if (player == nullptr) {
        return;
    }

    if (player->player != nullptr) {
        player->player->Stop();
        player->player->Shutdown();
        player->player->Release();
    }

    if (player->mediaItem != nullptr) {
        player->mediaItem->Release();
    }

    delete player;
    player = nullptr;
}

bool HasNewCommand(std::uint64_t serial) {
    std::lock_guard<std::mutex> lock(g_mutex);
    return g_shutdownRequested || g_commandSerial != serial;
}

void SetStateIfCurrent(std::uint64_t serial, PlaybackStage stage, const std::string& error) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (serial != g_commandSerial) {
        return;
    }

    g_stage = stage;
    g_lastError = Sanitize(error);
}

HRESULT StartPlayerFromUrl(
    const std::wstring& mediaUrl,
    int volume,
    PlayerHandle** playerOut,
    PlayerCallback** callbackOut,
    bool autoPlay = true) {
    if (playerOut == nullptr || callbackOut == nullptr) {
        return E_POINTER;
    }

    *playerOut = nullptr;
    *callbackOut = nullptr;

    std::string errorMessage;
    if (!EnsurePlaybackBackendReady(&errorMessage)) {
        DebugLog("mfplay|init_fail|error=" + errorMessage);
        return E_FAIL;
    }

    PlayerHandle* player = new PlayerHandle();
    PlayerCallback* callback = new PlayerCallback();

    if (mediaUrl.empty()) {
        delete player;
        callback->Release();
        return E_FAIL;
    }

    IMFPMediaPlayer* mediaPlayer = nullptr;
    const HRESULT createHr = MFPCreateMediaPlayer(
        mediaUrl.c_str(),
        autoPlay ? TRUE : FALSE,
        MFP_OPTION_FREE_THREADED_CALLBACK | MFP_OPTION_NO_REMOTE_DESKTOP_OPTIMIZATION,
        callback,
        nullptr,
        &mediaPlayer);
    if (FAILED(createHr) || mediaPlayer == nullptr) {
        delete player;
        callback->Release();
        return FAILED(createHr) ? createHr : E_FAIL;
    }

    player->player = mediaPlayer;
    player->sourceUrl = WideToUtf8(mediaUrl);
    callback->Reset();

    const HRESULT volumeHr = player->player->SetVolume(static_cast<float>(std::clamp(volume, 0, 100)) / 100.0f);
    if (FAILED(volumeHr)) {
        player->lastError = HResultMessage("mfplay_volume", volumeHr);
        StopAndReleasePlayer(player);
        callback->Release();
        return volumeHr;
    }

    IMFPMediaItem* mediaItem = nullptr;
    const HRESULT itemHr = player->player->GetMediaItem(&mediaItem);
    if (SUCCEEDED(itemHr) && mediaItem != nullptr) {
        player->mediaItem = mediaItem;
    }

    *playerOut = player;
    *callbackOut = callback;
    return S_OK;
}

HRESULT StartPlayerFromUrlAtPosition(
    const std::wstring& mediaUrl,
    int volume,
    std::int64_t startPositionMs,
    PlayerHandle** playerOut,
    PlayerCallback** callbackOut) {
    if (playerOut == nullptr || callbackOut == nullptr) {
        return E_POINTER;
    }

    *playerOut = nullptr;
    *callbackOut = nullptr;

    std::string errorMessage;
    if (!EnsurePlaybackBackendReady(&errorMessage)) {
        DebugLog("mfplay|init_fail|error=" + errorMessage);
        return E_FAIL;
    }

    PlayerHandle* player = new PlayerHandle();
    PlayerCallback* callback = new PlayerCallback();

    IMFPMediaPlayer* mediaPlayer = nullptr;
    const HRESULT createHr = MFPCreateMediaPlayer(
        nullptr,
        FALSE,
        MFP_OPTION_FREE_THREADED_CALLBACK | MFP_OPTION_NO_REMOTE_DESKTOP_OPTIMIZATION,
        callback,
        nullptr,
        &mediaPlayer);
    if (FAILED(createHr) || mediaPlayer == nullptr) {
        delete player;
        callback->Release();
        return FAILED(createHr) ? createHr : E_FAIL;
    }

    player->player = mediaPlayer;
    player->sourceUrl = WideToUtf8(mediaUrl);
    callback->Reset();

    const HRESULT volumeHr = player->player->SetVolume(static_cast<float>(std::clamp(volume, 0, 100)) / 100.0f);
    if (FAILED(volumeHr)) {
        player->lastError = HResultMessage("mfplay_volume", volumeHr);
        StopAndReleasePlayer(player);
        callback->Release();
        return volumeHr;
    }

    IMFPMediaItem* mediaItem = nullptr;
    const HRESULT itemHr = player->player->CreateMediaItemFromURL(mediaUrl.c_str(), TRUE, 0, &mediaItem);
    if (FAILED(itemHr) || mediaItem == nullptr) {
        StopAndReleasePlayer(player);
        callback->Release();
        return FAILED(itemHr) ? itemHr : E_FAIL;
    }

    PROPVARIANT startValue{};
    PropVariantInit(&startValue);
    startValue.vt = VT_I8;
    startValue.hVal.QuadPart = ClampPositionMs(startPositionMs) * kHundredNsPerMillisecond;
    const HRESULT positionHr = mediaItem->SetStartStopPosition(&MFP_POSITIONTYPE_100NS, &startValue, nullptr, nullptr);
    PropVariantClear(&startValue);
    if (FAILED(positionHr)) {
        mediaItem->Release();
        StopAndReleasePlayer(player);
        callback->Release();
        return positionHr;
    }

    const HRESULT setItemHr = player->player->SetMediaItem(mediaItem);
    if (FAILED(setItemHr)) {
        mediaItem->Release();
        StopAndReleasePlayer(player);
        callback->Release();
        return setItemHr;
    }

    player->mediaItem = mediaItem;

    std::string playError;
    if (!PlayPlayer(player, &playError)) {
        StopAndReleasePlayer(player);
        callback->Release();
        return E_FAIL;
    }

    *playerOut = player;
    *callbackOut = callback;
    return S_OK;
}

bool ResolveAudioStream(
    const std::string& input,
    std::wstring* mediaUrl,
    std::string* errorMessage,
    bool forceRefresh = false) {
    const auto startedAt = std::chrono::steady_clock::now();
    std::vector<char> buffer(32768, '\0');
    const std::string resolverInput = forceRefresh ? std::string(kForceRefreshPrefix) + input : input;
    const int status = YPM0(resolverInput.c_str(), buffer.data(), static_cast<int>(buffer.size()));
    const std::string payload(buffer.data());
    const auto elapsedMs = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - startedAt).count();
    if (status != 0) {
        DebugLog("resolve|fail|status=" + std::to_string(status) + "|elapsedMs=" + std::to_string(elapsedMs) + "|payload=" + Sanitize(payload));
        if (errorMessage != nullptr) {
            *errorMessage = payload.empty() ? "err|resolve_failed" : payload;
        }
        return false;
    }

    if (payload.rfind("err|", 0) == 0) {
        DebugLog("resolve|fail|elapsedMs=" + std::to_string(elapsedMs) + "|payload=" + Sanitize(payload));
        if (errorMessage != nullptr) {
            *errorMessage = payload;
        }
        return false;
    }

    const std::wstring path = Utf8ToWide(payload);
    if (path.empty()) {
        DebugLog("resolve|fail|elapsedMs=" + std::to_string(elapsedMs) + "|payload=empty_url");
        if (errorMessage != nullptr) {
            *errorMessage = "err|resolve_failed|empty_url";
        }
        return false;
    }

    if (mediaUrl != nullptr) {
        *mediaUrl = path;
    }

    DebugLog("resolve|ok|elapsedMs=" + std::to_string(elapsedMs) + "|urlLen=" + std::to_string(payload.size()));
    return true;
}

bool ResolveTrackTitle(const std::string& input, std::string* title, std::string* errorMessage) {
    std::vector<char> buffer(4096, '\0');
    const int status = YPM1(input.c_str(), buffer.data(), static_cast<int>(buffer.size()));
    const std::string payload(buffer.data());
    if (status != 0 || payload.rfind("err|", 0) == 0) {
        if (errorMessage != nullptr) {
            *errorMessage = payload.empty() ? "err|resolve_failed|title" : payload;
        }
        return false;
    }

    if (title != nullptr) {
        *title = Sanitize(TrimWhitespace(payload));
    }

    return title != nullptr && !title->empty();
}

bool ResolvePlaylist(
    const std::string& input,
    std::uint64_t* token,
    std::string* playlistTitle,
    std::size_t* itemCount,
    std::string* errorMessage) {
    std::vector<char> buffer(1024 * 1024, '\0');
    const int status = YPM3(input.c_str(), buffer.data(), static_cast<int>(buffer.size()));
    const std::string payload(buffer.data());
    if (status != 0 || payload.rfind("err|", 0) == 0) {
        if (errorMessage != nullptr) {
            *errorMessage = payload.empty() ? "err|resolve_failed|playlist" : payload;
        }
        return false;
    }

    const std::size_t metaPos = payload.find(kPlaylistMetaSeparator);
    if (metaPos == std::string::npos) {
        if (errorMessage != nullptr) {
            *errorMessage = "err|resolve_failed|playlist_payload";
        }
        return false;
    }

    std::string title = Sanitize(TrimWhitespace(payload.substr(0, metaPos)));
    std::vector<PlaylistEntry> items;
    const std::string itemPayload = payload.substr(metaPos + 1);
    if (!itemPayload.empty()) {
        for (const std::string& record : SplitByChar(itemPayload, kPlaylistRecordSeparator)) {
            if (record.empty()) {
                continue;
            }

            const std::size_t fieldPos = record.find(kPlaylistFieldSeparator);
            if (fieldPos == std::string::npos) {
                continue;
            }

            std::string url = StripWrappingQuotes(record.substr(0, fieldPos));
            url = Sanitize(url);
            if (url.empty()) {
                continue;
            }

            std::string itemTitle = Sanitize(TrimWhitespace(record.substr(fieldPos + 1)));
            if (itemTitle.empty()) {
                itemTitle = url;
            }

            items.push_back({url, itemTitle});
        }
    }

    if (items.empty()) {
        if (errorMessage != nullptr) {
            *errorMessage = "err|resolve_failed|playlist_empty";
        }
        return false;
    }

    if (title.empty()) {
        title = items.front().title;
    }

    std::lock_guard<std::mutex> lock(g_mutex);
    g_playlistItems = std::move(items);
    g_playlistTitle = title;
    ++g_playlistToken;

    if (token != nullptr) {
        *token = g_playlistToken;
    }

    if (playlistTitle != nullptr) {
        *playlistTitle = g_playlistTitle;
    }

    if (itemCount != nullptr) {
        *itemCount = g_playlistItems.size();
    }

    return true;
}

bool GetCachedPlaylistItem(std::uint64_t token, int index, PlaylistEntry* entry) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (token == 0 || token != g_playlistToken || index < 0 || index >= static_cast<int>(g_playlistItems.size())) {
        return false;
    }

    if (entry != nullptr) {
        *entry = g_playlistItems[static_cast<std::size_t>(index)];
    }

    return true;
}

bool TryUsePrefetchedResolve(const std::string& input, std::wstring* mediaUrl) {
    std::unique_lock<std::mutex> lock(g_mutex);
    if (input.empty() || input != g_prefetchUrl) {
        return false;
    }

    const std::uint64_t serial = g_prefetchSerial;
    while (!g_shutdownRequested && g_prefetchRunning && serial == g_prefetchSerial && input == g_prefetchUrl) {
        g_prefetchCv.wait(lock);
    }

    if (g_shutdownRequested || serial != g_prefetchSerial || input != g_prefetchUrl || g_prefetchRunning || g_prefetchResolvedUrl.empty()) {
        return false;
    }

    if (mediaUrl != nullptr) {
        *mediaUrl = g_prefetchResolvedUrl;
    }

    return true;
}

void PrefetchWorker(std::uint64_t serial, std::string url) {
    DebugLog("prefetch|begin|serial=" + std::to_string(serial) + "|url=" + Sanitize(url));
    std::wstring resolvedUrl;
    std::string errorMessage;
    const bool resolved = ResolveAudioStream(url, &resolvedUrl, &errorMessage);

    std::lock_guard<std::mutex> lock(g_mutex);
    if (serial != g_prefetchSerial || url != g_prefetchUrl) {
        g_prefetchCv.notify_all();
        return;
    }

    g_prefetchRunning = false;
    g_prefetchResolvedUrl = resolved ? std::move(resolvedUrl) : std::wstring();
    g_prefetchError = resolved ? std::string() : Sanitize(errorMessage);
    g_prefetchCv.notify_all();
    DebugLog(std::string("prefetch|") + (resolved ? "ok" : "fail") + "|serial=" + std::to_string(serial) +
             (resolved ? std::string() : "|error=" + g_prefetchError));
}

void StartPrefetchLocked(const std::string& url) {
    if (url.empty()) {
        return;
    }

    if (g_prefetchRunning && g_prefetchUrl == url) {
        return;
    }

    if (!g_prefetchRunning && g_prefetchUrl == url && !g_prefetchResolvedUrl.empty()) {
        return;
    }

    ++g_prefetchSerial;
    g_prefetchRunning = true;
    g_prefetchUrl = url;
    g_prefetchResolvedUrl.clear();
    g_prefetchError.clear();

    const std::uint64_t serial = g_prefetchSerial;
    std::thread([serial, url]() {
        PrefetchWorker(serial, url);
    }).detach();
}

void WarmupBackendAsync() {
    DebugLog("warmup|begin");
    std::vector<char> buffer(512, '\0');
    const int warmupStatus = YPM2(buffer.data(), static_cast<int>(buffer.size()));
    DebugLog("warmup|" + std::string(warmupStatus == 0 ? "ok" : "fail") + "|payload=" + Sanitize(buffer.data()));

    std::lock_guard<std::mutex> lock(g_mutex);
    g_warmupRequested = false;
    g_warmupCompleted = warmupStatus == 0;
}

bool SetPlayerVolume(PlayerHandle* player, int volume, std::string* errorMessage = nullptr) {
    if (player == nullptr || player->player == nullptr) {
        if (errorMessage != nullptr) {
            *errorMessage = "mfplay|volume_unavailable";
        }
        return false;
    }

    const int clampedVolume = std::clamp(volume, 0, 100);
    const HRESULT hr = player->player->SetVolume(static_cast<float>(clampedVolume) / 100.0f);
    if (FAILED(hr)) {
        const std::string message = HResultMessage("mfplay_volume", hr);
        player->lastError = message;
        if (errorMessage != nullptr) {
            *errorMessage = message;
        }
        return false;
    }

    return true;
}

void UpdateTimelineFromPlayer(PlayerHandle* player, PlayerCallback* callback = nullptr) {
    if (player == nullptr || player->player == nullptr) {
        ResetTimelineState();
        return;
    }

    PROPVARIANT positionValue{};
    PROPVARIANT durationValue{};
    PropVariantInit(&positionValue);
    PropVariantInit(&durationValue);

    std::int64_t positionMs = 0;
    std::int64_t durationMs = 0;

    if (SUCCEEDED(player->player->GetPosition(MFP_POSITIONTYPE_100NS, &positionValue))) {
        std::int64_t position100ns = 0;
        if (TryReadPropVariantInt64(positionValue, &position100ns)) {
            positionMs = std::max<std::int64_t>(0, position100ns / kHundredNsPerMillisecond);
        }
    }

    if (SUCCEEDED(player->player->GetDuration(MFP_POSITIONTYPE_100NS, &durationValue))) {
        std::int64_t duration100ns = 0;
        if (TryReadPropVariantInt64(durationValue, &duration100ns)) {
            durationMs = std::max<std::int64_t>(0, duration100ns / kHundredNsPerMillisecond);
        }
    }

    PropVariantClear(&positionValue);
    PropVariantClear(&durationValue);

    g_timelinePositionMs.store(positionMs);
    g_timelineDurationMs.store(durationMs);
    UpdateCallbackFromPlayer(player, callback);
}

std::int64_t ReadPlayerPositionMs(PlayerHandle* player) {
    if (player == nullptr || player->player == nullptr) {
        return -1;
    }

    PROPVARIANT value{};
    PropVariantInit(&value);
    const HRESULT hr = player->player->GetPosition(MFP_POSITIONTYPE_100NS, &value);
    if (FAILED(hr)) {
        PropVariantClear(&value);
        return -1;
    }

    std::int64_t position100ns = 0;
    const bool ok = TryReadPropVariantInt64(value, &position100ns);
    PropVariantClear(&value);
    if (!ok) {
        return -1;
    }

    return std::max<std::int64_t>(0, position100ns / kHundredNsPerMillisecond);
}

bool SeekPlayerInPlace(
    PlayerHandle* player,
    std::int64_t requestedMs,
    std::uint64_t serial,
    bool paused,
    std::chrono::milliseconds verifyTimeout = std::chrono::milliseconds(1200),
    std::int64_t progressThresholdMs = 120) {
    if (player == nullptr) {
        return false;
    }

    const std::int64_t initialPositionMs = ReadPlayerPositionMs(player);
    const std::int64_t durationMs = g_timelineDurationMs.load();
    const std::int64_t jumpDistanceMs = initialPositionMs >= 0
        ? std::llabs(requestedMs - initialPositionMs)
        : requestedMs;
    const bool largeSeek = jumpDistanceMs >= 120000 || requestedMs >= 900000 || durationMs >= 1800000;
    const auto effectiveVerifyTimeout = largeSeek
        ? std::max(verifyTimeout, std::chrono::milliseconds(5000))
        : verifyTimeout;
    const bool allowSettledSuccess = !largeSeek;

    const auto startedAt = std::chrono::steady_clock::now();
    DebugLog("seek_in_place|begin|serial=" + std::to_string(serial) + "|requestedMs=" + std::to_string(requestedMs) +
             "|paused=" + std::to_string(paused ? 1 : 0) +
             "|initialMs=" + std::to_string(initialPositionMs) +
             "|jumpMs=" + std::to_string(jumpDistanceMs) +
             "|durationMs=" + std::to_string(durationMs) +
             "|largeSeek=" + std::to_string(largeSeek ? 1 : 0));

    bool pausedForSeek = false;
    if (!paused) {
        std::string pauseError;
        if (!PausePlayer(player, &pauseError)) {
            DebugLog("seek_in_place|fail|step=pause|error=" + pauseError);
            return false;
        }

        pausedForSeek = true;
    }

    std::string seekError;
    if (!SetPlayerPositionMs(player, requestedMs, &seekError)) {
        DebugLog("seek_in_place|fail|step=set_position|error=" + seekError);
        return false;
    }

    g_timelinePositionMs.store(requestedMs);

    if (pausedForSeek) {
        std::string resumeError;
        if (!PlayPlayer(player, &resumeError)) {
            DebugLog("seek_in_place|fail|step=resume|error=" + resumeError);
            return false;
        }
    }

    const std::int64_t toleranceMs = std::max<std::int64_t>(3000, std::min<std::int64_t>(10000, requestedMs / 20));
    const auto verifyDeadline = std::chrono::steady_clock::now() + (paused ? std::chrono::milliseconds(400) : effectiveVerifyTimeout);
    std::int64_t lastObservedMs = requestedMs;
    bool reachedTarget = false;
    auto reachedTargetAt = std::chrono::steady_clock::time_point{};
    bool playRetryIssued = false;

    while (std::chrono::steady_clock::now() < verifyDeadline) {
        std::this_thread::sleep_for(std::chrono::milliseconds(40));
        const std::int64_t currentPositionMs = ReadPlayerPositionMs(player);
        if (currentPositionMs >= 0) {
            lastObservedMs = currentPositionMs;
            g_timelinePositionMs.store(currentPositionMs);
            if (!reachedTarget && std::llabs(currentPositionMs - requestedMs) <= toleranceMs) {
                reachedTarget = true;
                reachedTargetAt = std::chrono::steady_clock::now();
                if (paused) {
                    const auto elapsedMs = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - startedAt).count();
                    DebugLog("seek_in_place|ok|paused=1|elapsedMs=" + std::to_string(elapsedMs) + "|observedMs=" + std::to_string(currentPositionMs));
                    SetStateIfCurrent(serial, PlaybackStage::Paused, "");
                    return true;
                }
            }

            if (reachedTarget && !paused && currentPositionMs >= (requestedMs + progressThresholdMs)) {
                const auto elapsedMs = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - startedAt).count();
                DebugLog("seek_in_place|ok|paused=0|elapsedMs=" + std::to_string(elapsedMs) + "|observedMs=" + std::to_string(currentPositionMs));
                SetStateIfCurrent(serial, PlaybackStage::Playing, "");
                return true;
            }

            if (allowSettledSuccess && reachedTarget && !paused) {
                const auto settledFor = std::chrono::steady_clock::now() - reachedTargetAt;
                if (settledFor >= std::chrono::milliseconds(160) &&
                    currentPositionMs >= std::max<std::int64_t>(0, requestedMs - toleranceMs)) {
                    const auto elapsedMs = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - startedAt).count();
                    DebugLog("seek_in_place|ok|paused=0|elapsedMs=" + std::to_string(elapsedMs) + "|observedMs=" + std::to_string(currentPositionMs) + "|mode=settled");
                    SetStateIfCurrent(serial, PlaybackStage::Playing, "");
                    return true;
                }
            }

            if (largeSeek && reachedTarget && !paused) {
                const auto settledFor = std::chrono::steady_clock::now() - reachedTargetAt;
                const PlayerState state = GetPlayerState(player);
                if (settledFor >= std::chrono::milliseconds(280) &&
                    (playRetryIssued || state == PlayerState::Playing) &&
                    currentPositionMs >= std::max<std::int64_t>(0, requestedMs - toleranceMs)) {
                    const auto elapsedMs = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - startedAt).count();
                    DebugLog("seek_in_place|ok|paused=0|elapsedMs=" + std::to_string(elapsedMs) +
                             "|observedMs=" + std::to_string(currentPositionMs) +
                             "|mode=target_reached");
                    SetStateIfCurrent(serial, PlaybackStage::Playing, "");
                    return true;
                }
            }

            if (largeSeek && reachedTarget && !paused && !playRetryIssued) {
                const auto settledFor = std::chrono::steady_clock::now() - reachedTargetAt;
                if (settledFor >= std::chrono::milliseconds(180)) {
                    std::string retryError;
                    if (PlayPlayer(player, &retryError)) {
                        playRetryIssued = true;
                        DebugLog("seek_in_place|play_retry|requestedMs=" + std::to_string(requestedMs) +
                                 "|observedMs=" + std::to_string(currentPositionMs));
                    } else {
                        DebugLog("seek_in_place|play_retry_fail|error=" + retryError);
                    }
                }
            }
        }
    }

    if (largeSeek && reachedTarget && !paused) {
        const auto elapsedMs = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - startedAt).count();
        DebugLog("seek_in_place|ok|paused=0|elapsedMs=" + std::to_string(elapsedMs) +
                 "|observedMs=" + std::to_string(lastObservedMs) +
                 "|mode=target_only_timeout");
        SetStateIfCurrent(serial, PlaybackStage::Playing, "");
        return true;
    }

    DebugLog(
        "seek_in_place|fallback|observedMs=" + std::to_string(lastObservedMs) +
        "|requestedMs=" + std::to_string(requestedMs) +
        "|reachedTarget=" + std::to_string(reachedTarget ? 1 : 0) +
        "|largeSeek=" + std::to_string(largeSeek ? 1 : 0));
    return false;
}

enum class SeekRestartResult {
    Success,
    Superseded,
    Failure
};

SeekRestartResult VerifyRestartedPlayerProgress(
    PlayerHandle* player,
    PlayerCallback* callback,
    std::int64_t requestedMs,
    std::uint64_t serial,
    bool paused,
    std::int64_t* observedMsOut = nullptr) {
    if (observedMsOut != nullptr) {
        *observedMsOut = requestedMs;
    }

    if (player == nullptr) {
        return SeekRestartResult::Failure;
    }

    const std::int64_t toleranceMs = std::max<std::int64_t>(3000, std::min<std::int64_t>(10000, requestedMs / 20));
    const std::int64_t progressThresholdMs = 120;
    const auto verifyDeadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(paused ? 1200 : 3000);
    std::int64_t lastObservedMs = requestedMs;
    bool reachedTarget = false;

    while (std::chrono::steady_clock::now() < verifyDeadline) {
        if (HasNewCommand(serial)) {
            DebugLog("seek_restart|superseded|reason=new_command|serial=" + std::to_string(serial));
            if (observedMsOut != nullptr) {
                *observedMsOut = lastObservedMs;
            }
            return SeekRestartResult::Superseded;
        }

        const std::int64_t pendingSeekMs = g_pendingSeekMs.load();
        if (pendingSeekMs >= 0 && pendingSeekMs != requestedMs) {
            DebugLog("seek_restart|superseded|reason=new_seek|requestedMs=" + std::to_string(requestedMs) +
                     "|nextRequestedMs=" + std::to_string(pendingSeekMs));
            if (observedMsOut != nullptr) {
                *observedMsOut = lastObservedMs;
            }
            return SeekRestartResult::Superseded;
        }

        UpdateCallbackFromPlayer(player, callback);
        if (callback != nullptr && callback->SawError()) {
            DebugLog("seek_restart|fail|step=callback_error|error=" + callback->LastErrorMessage());
            if (observedMsOut != nullptr) {
                *observedMsOut = lastObservedMs;
            }
            return SeekRestartResult::Failure;
        }

        UpdateTimelineFromPlayer(player, callback);
        const std::int64_t currentPositionMs = ReadPlayerPositionMs(player);
        if (currentPositionMs >= 0) {
            lastObservedMs = currentPositionMs;
            g_timelinePositionMs.store(currentPositionMs);
            if (!reachedTarget && std::llabs(currentPositionMs - requestedMs) <= toleranceMs) {
                reachedTarget = true;
                if (paused) {
                    if (observedMsOut != nullptr) {
                        *observedMsOut = currentPositionMs;
                    }
                    return SeekRestartResult::Success;
                }
            }

            if (reachedTarget && !paused && currentPositionMs >= (requestedMs + progressThresholdMs)) {
                if (observedMsOut != nullptr) {
                    *observedMsOut = currentPositionMs;
                }
                return SeekRestartResult::Success;
            }
        }

        std::this_thread::sleep_for(std::chrono::milliseconds(40));
    }

    if (observedMsOut != nullptr) {
        *observedMsOut = lastObservedMs;
    }
    return SeekRestartResult::Failure;
}

SeekRestartResult WaitForPlayerStartup(
    PlayerHandle* player,
    PlayerCallback* callback,
    std::uint64_t serial,
    std::int64_t* observedMsOut = nullptr) {
    if (observedMsOut != nullptr) {
        *observedMsOut = 0;
    }

    if (player == nullptr) {
        return SeekRestartResult::Failure;
    }

    const auto verifyDeadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(9000);
    std::int64_t lastObservedMs = 0;
    while (std::chrono::steady_clock::now() < verifyDeadline) {
        if (HasNewCommand(serial)) {
            DebugLog("seek_restart|startup_superseded|reason=new_command|serial=" + std::to_string(serial));
            if (observedMsOut != nullptr) {
                *observedMsOut = lastObservedMs;
            }
            return SeekRestartResult::Superseded;
        }

        const std::int64_t pendingSeekMs = g_pendingSeekMs.load();
        if (pendingSeekMs >= 0) {
            DebugLog("seek_restart|startup_superseded|reason=new_seek|nextRequestedMs=" + std::to_string(pendingSeekMs));
            if (observedMsOut != nullptr) {
                *observedMsOut = lastObservedMs;
            }
            return SeekRestartResult::Superseded;
        }

        UpdateCallbackFromPlayer(player, callback);
        if (callback != nullptr && callback->SawError()) {
            DebugLog("seek_restart|startup_fail|step=callback_error|error=" + callback->LastErrorMessage());
            if (observedMsOut != nullptr) {
                *observedMsOut = lastObservedMs;
            }
            return SeekRestartResult::Failure;
        }

        UpdateTimelineFromPlayer(player, callback);
        const std::int64_t currentPositionMs = ReadPlayerPositionMs(player);
        if (currentPositionMs >= 0) {
            lastObservedMs = currentPositionMs;
            g_timelinePositionMs.store(currentPositionMs);
        }

        if ((callback != nullptr && callback->SawPlay()) || currentPositionMs > 200) {
            if (observedMsOut != nullptr) {
                *observedMsOut = lastObservedMs;
            }
            return SeekRestartResult::Success;
        }

        std::this_thread::sleep_for(std::chrono::milliseconds(40));
    }

    if (observedMsOut != nullptr) {
        *observedMsOut = lastObservedMs;
    }
    return SeekRestartResult::Failure;
}

SeekRestartResult WaitForPlayerPlaybackReady(
    PlayerHandle* player,
    PlayerCallback* callback,
    std::uint64_t serial,
    std::int64_t* observedMsOut = nullptr) {
    if (observedMsOut != nullptr) {
        *observedMsOut = 0;
    }

    if (player == nullptr) {
        return SeekRestartResult::Failure;
    }

    const auto verifyDeadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(9000);
    std::int64_t lastObservedMs = 0;
    while (std::chrono::steady_clock::now() < verifyDeadline) {
        if (HasNewCommand(serial)) {
            if (observedMsOut != nullptr) {
                *observedMsOut = lastObservedMs;
            }
            return SeekRestartResult::Superseded;
        }

        const std::int64_t pendingSeekMs = g_pendingSeekMs.load();
        if (pendingSeekMs >= 0) {
            if (observedMsOut != nullptr) {
                *observedMsOut = lastObservedMs;
            }
            return SeekRestartResult::Superseded;
        }

        UpdateCallbackFromPlayer(player, callback);
        if (callback != nullptr && callback->SawError()) {
            if (observedMsOut != nullptr) {
                *observedMsOut = lastObservedMs;
            }
            return SeekRestartResult::Failure;
        }

        UpdateTimelineFromPlayer(player, callback);
        const std::int64_t currentPositionMs = ReadPlayerPositionMs(player);
        if (currentPositionMs >= 0) {
            lastObservedMs = currentPositionMs;
            g_timelinePositionMs.store(currentPositionMs);
        }

        const PlayerState state = GetPlayerState(player);
        if ((callback != nullptr && callback->SawPlay()) || state == PlayerState::Playing) {
            if (observedMsOut != nullptr) {
                *observedMsOut = lastObservedMs;
            }
            return SeekRestartResult::Success;
        }

        std::this_thread::sleep_for(std::chrono::milliseconds(40));
    }

    if (observedMsOut != nullptr) {
        *observedMsOut = lastObservedMs;
    }
    return SeekRestartResult::Failure;
}

bool RestartPlayerAtPosition(
    PlayerHandle*& player,
    PlayerCallback*& callback,
    const std::wstring& mediaUrl,
    int volume,
    std::int64_t requestedMs,
    std::uint64_t serial,
    bool paused) {
    const auto startedAt = std::chrono::steady_clock::now();
    DebugLog("seek_restart|begin|serial=" + std::to_string(serial) + "|requestedMs=" + std::to_string(requestedMs) +
             "|paused=" + std::to_string(paused ? 1 : 0));
    const std::int64_t previousDurationMs = g_timelineDurationMs.load();
    StopAndReleasePlayer(player);
    if (callback != nullptr) {
        callback->Release();
        callback = nullptr;
    }

    ResetTimelineState();
    const bool preferAutoplayRestart = requestedMs >= 900000 || previousDurationMs >= 1800000;

    auto runAutoplayRecovery = [&]() -> bool {
        DebugLog("seek_restart|recover_begin|requestedMs=" + std::to_string(requestedMs) +
                 "|preferAutoplay=" + std::to_string(preferAutoplayRestart ? 1 : 0));

        StopAndReleasePlayer(player);
        if (callback != nullptr) {
            callback->Release();
            callback = nullptr;
        }
        ResetTimelineState();

        HRESULT hr = preferAutoplayRestart
            ? StartPlayerFromUrlAtPosition(mediaUrl, volume, requestedMs, &player, &callback)
            : StartPlayerFromUrl(mediaUrl, volume, &player, &callback, true);
        if (FAILED(hr)) {
            DebugLog("seek_restart|recover_fail|step=start_autoplay|error=mfplay|start_failed");
            SetStateIfCurrent(serial, PlaybackStage::Error, "mfplay|start_failed");
            return false;
        }

        std::int64_t startupObservedMs = 0;
        const SeekRestartResult startupResult = preferAutoplayRestart
            ? WaitForPlayerPlaybackReady(player, callback, serial, &startupObservedMs)
            : WaitForPlayerStartup(player, callback, serial, &startupObservedMs);
        if (startupResult == SeekRestartResult::Superseded) {
            DebugLog("seek_restart|recover_superseded|step=startup|observedMs=" + std::to_string(startupObservedMs));
            return true;
        }

        if (startupResult == SeekRestartResult::Failure) {
            DebugLog("seek_restart|recover_fail|step=startup_timeout|observedMs=" + std::to_string(startupObservedMs));
            SetStateIfCurrent(serial, PlaybackStage::Error, "mfplay|restart_start_timeout");
            return false;
        }

        if (paused) {
            std::string pauseError;
            if (!PausePlayer(player, &pauseError)) {
                DebugLog("seek_restart|recover_fail|step=pause_after_start|error=" + pauseError);
                SetStateIfCurrent(serial, PlaybackStage::Error, pauseError);
                return false;
            }
        }

        if (preferAutoplayRestart) {
            std::int64_t observedMs = startupObservedMs;
            const SeekRestartResult verifyResult = VerifyRestartedPlayerProgress(player, callback, requestedMs, serial, paused, &observedMs);
            if (verifyResult == SeekRestartResult::Success || verifyResult == SeekRestartResult::Superseded) {
                const auto recoveredElapsedMs = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - startedAt).count();
                DebugLog("seek_restart|recover_ok|paused=" + std::to_string(paused ? 1 : 0) +
                         "|elapsedMs=" + std::to_string(recoveredElapsedMs) +
                         "|observedMs=" + std::to_string(observedMs) +
                         "|mode=start_position");
                SetStateIfCurrent(serial, paused ? PlaybackStage::Paused : PlaybackStage::Playing, "");
                return true;
            }
        } else if (SeekPlayerInPlace(player, requestedMs, serial, paused, std::chrono::milliseconds(4500), 120)) {
            const auto recoveredElapsedMs = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - startedAt).count();
            DebugLog("seek_restart|recover_ok|paused=" + std::to_string(paused ? 1 : 0) +
                     "|elapsedMs=" + std::to_string(recoveredElapsedMs));
            SetStateIfCurrent(serial, paused ? PlaybackStage::Paused : PlaybackStage::Playing, "");
            return true;
        }

        const auto failedElapsedMs = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - startedAt).count();
        DebugLog("seek_restart|recover_fail|step=seek_in_place_after_start|elapsedMs=" + std::to_string(failedElapsedMs) +
                 "|requestedMs=" + std::to_string(requestedMs));
        SetStateIfCurrent(serial, PlaybackStage::Error, "mfseek|restart_timeout");
        return false;
    };

    if (preferAutoplayRestart) {
        return runAutoplayRecovery();
    }

    HRESULT hr = StartPlayerFromUrl(mediaUrl, volume, &player, &callback, false);
    if (FAILED(hr)) {
        DebugLog("seek_restart|fail|step=start|error=mfplay|start_failed");
        SetStateIfCurrent(serial, PlaybackStage::Error, "mfplay|start_failed");
        return false;
    }

    std::string seekError;
    if (!SetPlayerPositionMs(player, requestedMs, &seekError)) {
        DebugLog("seek_restart|fail|step=set_position|error=" + seekError);
        SetStateIfCurrent(serial, PlaybackStage::Error, seekError);
        return false;
    }

    g_timelinePositionMs.store(requestedMs);

    if (!paused) {
        std::string playError;
        if (!PlayPlayer(player, &playError)) {
            DebugLog("seek_restart|fail|step=resume|error=" + playError);
            SetStateIfCurrent(serial, PlaybackStage::Error, playError);
            return false;
        }
    }

    std::int64_t observedMs = requestedMs;
    const SeekRestartResult verifyResult = VerifyRestartedPlayerProgress(player, callback, requestedMs, serial, paused, &observedMs);
    const auto elapsedMs = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - startedAt).count();
    if (verifyResult == SeekRestartResult::Success) {
        DebugLog("seek_restart|ok|paused=" + std::to_string(paused ? 1 : 0) +
                 "|elapsedMs=" + std::to_string(elapsedMs) +
                 "|observedMs=" + std::to_string(observedMs));
        SetStateIfCurrent(serial, paused ? PlaybackStage::Paused : PlaybackStage::Playing, "");
        return true;
    }

    if (verifyResult == SeekRestartResult::Superseded) {
        DebugLog("seek_restart|superseded|paused=" + std::to_string(paused ? 1 : 0) +
                 "|elapsedMs=" + std::to_string(elapsedMs) +
                 "|observedMs=" + std::to_string(observedMs));
        return true;
    }

    return runAutoplayRecovery();
}

bool ApplyPendingSeekIfNeeded(
    PlayerHandle*& player,
    PlayerCallback*& callback,
    const std::wstring& mediaUrl,
    int volume,
    std::uint64_t serial,
    bool paused) {
    if (player == nullptr) {
        return true;
    }

    std::int64_t requestedMs = g_pendingSeekMs.exchange(-1);
    if (requestedMs < 0) {
        return true;
    }

    std::int64_t durationMs = g_timelineDurationMs.load();
    if (durationMs > 0) {
        requestedMs = std::min(requestedMs, durationMs);
    }
    requestedMs = ClampPositionMs(requestedMs);

    if (SeekPlayerInPlace(player, requestedMs, serial, paused)) {
        return true;
    }

    SetStateIfCurrent(serial, PlaybackStage::Resolving, "");
    return RestartPlayerAtPosition(player, callback, mediaUrl, volume, requestedMs, serial, paused);
}

void WorkerMain() {
    PlayerHandle* player = nullptr;
    PlayerCallback* callback = nullptr;
    std::uint64_t handledSerial = 0;
    int activeVolume = 70;

    std::unique_lock<std::mutex> lock(g_mutex);
    while (!g_shutdownRequested) {
        g_commandCv.wait(lock, [&]() { return g_shutdownRequested || g_commandSerial != handledSerial; });
        if (g_shutdownRequested) {
            break;
        }

        handledSerial = g_commandSerial;
        const bool shouldPlay = g_commandIsPlay;
        const std::string url = g_commandUrl;
        const int volume = g_commandVolume;
        lock.unlock();
        DebugLog(std::string("worker_command|") + (shouldPlay ? "play" : "stop") + "|serial=" + std::to_string(handledSerial) +
                 "|volume=" + std::to_string(volume) + "|url=" + Sanitize(url));

        StopAndReleasePlayer(player);
        if (callback != nullptr) {
            callback->Release();
            callback = nullptr;
        }
        ResetTimelineState();
        ClearPendingSeekState();

        if (!shouldPlay) {
            SetStateIfCurrent(handledSerial, PlaybackStage::Idle, "");
            lock.lock();
            continue;
        }

        SetStateIfCurrent(handledSerial, PlaybackStage::Resolving, "");

        std::wstring resolvedUrl;
        std::string prepareError;
        const bool usedPrefetch = TryUsePrefetchedResolve(url, &resolvedUrl);
        if (!usedPrefetch && !ResolveAudioStream(url, &resolvedUrl, &prepareError)) {
            DebugLog("worker_command|resolve_fail|serial=" + std::to_string(handledSerial) + "|error=" + prepareError);
            SetStateIfCurrent(handledSerial, PlaybackStage::Error, prepareError);
            lock.lock();
            continue;
        }

        DebugLog(std::string("worker_command|resolve_") + (usedPrefetch ? "prefetch" : "direct") +
                 "|serial=" + std::to_string(handledSerial));

        if (HasNewCommand(handledSerial)) {
            lock.lock();
            continue;
        }

        {
            std::lock_guard<std::mutex> stateLock(g_mutex);
            activeVolume = g_commandVolume;
        }

        HRESULT hr = StartPlayerFromUrl(resolvedUrl, activeVolume, &player, &callback);
        if (FAILED(hr) && !HasNewCommand(handledSerial)) {
            DebugLog("worker_command|start_fail_first|serial=" + std::to_string(handledSerial) + "|error=start_failed");
            std::wstring retriedUrl;
            std::string retryError;
            if (ResolveAudioStream(url, &retriedUrl, &retryError)) {
                hr = StartPlayerFromUrl(retriedUrl, activeVolume, &player, &callback);
                if (SUCCEEDED(hr)) {
                    resolvedUrl = std::move(retriedUrl);
                    DebugLog("worker_command|retry_ok|serial=" + std::to_string(handledSerial));
                }
            }
        }

        if (FAILED(hr)) {
            DebugLog("worker_command|start_fail_final|serial=" + std::to_string(handledSerial) + "|error=start_failed");
            SetStateIfCurrent(handledSerial, PlaybackStage::Error, "mfplay|start_failed");
            lock.lock();
            continue;
        }

        UpdateTimelineFromPlayer(player, callback);

        bool failed = false;
        bool started = false;
        bool paused = false;
        int automaticRecoveryAttempts = 0;
        while (!HasNewCommand(handledSerial)) {
            bool pauseRequested = false;
            {
                std::lock_guard<std::mutex> stateLock(g_mutex);
                pauseRequested = g_pauseRequested;
            }

            if (pauseRequested && !paused && player != nullptr) {
                std::string pauseError;
                if (!PausePlayer(player, &pauseError)) {
                    SetStateIfCurrent(handledSerial, PlaybackStage::Error, pauseError);
                    failed = true;
                    break;
                }

                paused = true;
                SetStateIfCurrent(handledSerial, PlaybackStage::Paused, "");
            } else if (!pauseRequested && paused && player != nullptr) {
                std::string resumeError;
                if (!PlayPlayer(player, &resumeError)) {
                    SetStateIfCurrent(handledSerial, PlaybackStage::Error, resumeError);
                    failed = true;
                    break;
                }

                paused = false;
                SetStateIfCurrent(handledSerial, PlaybackStage::Playing, "");
            }

            const int pendingVolume = g_pendingVolume.exchange(-1);
            if (pendingVolume >= 0) {
                std::string volumeError;
                if (SetPlayerVolume(player, pendingVolume, &volumeError)) {
                    activeVolume = pendingVolume;
                    DebugLog("volume|applied|value=" + std::to_string(pendingVolume));
                } else {
                    DebugLog("volume|apply_fail|value=" + std::to_string(pendingVolume) + "|error=" + volumeError);
                }
            }

            if (!ApplyPendingSeekIfNeeded(player, callback, resolvedUrl, activeVolume, handledSerial, paused)) {
                failed = true;
                break;
            }

            UpdateTimelineFromPlayer(player, callback);

            if (callback != nullptr && callback->SawError()) {
                const std::string playbackError = callback->LastErrorMessage();
                const std::int64_t recoveryPositionMs = ReadPlayerPositionMs(player);
                std::string refreshError;
                if (started && recoveryPositionMs >= 0 && automaticRecoveryAttempts < 2) {
                    ++automaticRecoveryAttempts;
                    SetStateIfCurrent(handledSerial, PlaybackStage::Resolving, "");
                    DebugLog("playback_recovery|begin|attempt=" + std::to_string(automaticRecoveryAttempts) +
                             "|positionMs=" + std::to_string(recoveryPositionMs));

                    std::wstring refreshedUrl;
                    if (ResolveAudioStream(url, &refreshedUrl, &refreshError, true) &&
                        RestartPlayerAtPosition(
                            player,
                            callback,
                            refreshedUrl,
                            activeVolume,
                            recoveryPositionMs,
                            handledSerial,
                            paused)) {
                        resolvedUrl = std::move(refreshedUrl);
                        DebugLog("playback_recovery|ok|attempt=" + std::to_string(automaticRecoveryAttempts));
                        continue;
                    }

                    DebugLog("playback_recovery|fail|attempt=" + std::to_string(automaticRecoveryAttempts) +
                             "|error=" + Sanitize(refreshError));
                }

                const std::string finalError = !refreshError.empty()
                    ? refreshError
                    : (callback != nullptr ? callback->LastErrorMessage() : playbackError);
                SetStateIfCurrent(handledSerial, PlaybackStage::Error, finalError);
                failed = true;
                break;
            }

            if (!started && callback != nullptr && callback->SawPlay()) {
                SetStateIfCurrent(handledSerial, PlaybackStage::Playing, "");
                started = true;
            }

            if (paused) {
                std::this_thread::sleep_for(std::chrono::milliseconds(50));
                continue;
            }

            if (callback != nullptr && callback->PlaybackEnded()) {
                break;
            }

            if (player == nullptr) {
                break;
            }

            std::this_thread::sleep_for(std::chrono::milliseconds(50));
        }

        const bool interrupted = HasNewCommand(handledSerial);
        StopAndReleasePlayer(player);
        ResetTimelineState();
        if (callback != nullptr) {
            callback->Release();
            callback = nullptr;
        }

        if (!interrupted && !failed) {
            SetStateIfCurrent(handledSerial, PlaybackStage::Idle, "");
        }

        lock.lock();
    }

    lock.unlock();
    StopAndReleasePlayer(player);
    if (callback != nullptr) {
        callback->Release();
    }
    ShutdownPlaybackBackendThread();
}

void EnsureWorkerStartedLocked() {
    if (g_workerStarted) {
        return;
    }

    std::thread(WorkerMain).detach();
    g_workerStarted = true;
}

std::string GetStatus() {
    std::lock_guard<std::mutex> lock(g_mutex);
    const std::string status = GetStageName(g_stage);

    if (g_lastError.empty()) {
        return std::string("ok|status|") + status;
    }

    return std::string("ok|status|") + status + "|" + g_lastError;
}

std::string GetTimeline() {
    std::lock_guard<std::mutex> lock(g_mutex);
    return "ok|timeline|" + GetStageName(g_stage) + "|" +
           std::to_string(g_timelinePositionMs.load()) + "|" +
           std::to_string(g_timelineDurationMs.load());
}

std::pair<std::string, int> HandleCommand(const std::string& command, const std::vector<std::string>& args) {
    const std::string lower = a3yt::ToLowerAscii(command);

    if (lower.empty() || lower == "version" || lower == "ping" || lower == "help") {
        return {std::string("ok|version|") + kVersion, 0};
    }

    if (lower == "debug") {
        if (args.empty()) {
            return {
                "ok|debug|" + std::string(g_debugEnabled.load() ? "1" : "0") + "|" + Sanitize(WideToUtf8(GetDebugLogPath().wstring())),
                0
            };
        }

        bool enabled = false;
        if (!TryParseBoolLoose(args[0], &enabled)) {
            return {"err|invalid_argument|debug", 2};
        }

        if (!enabled && g_debugEnabled.load()) {
            DebugLog("debug|disabled");
        }

        g_debugEnabled.store(enabled);
        if (enabled) {
            DebugLog("debug|enabled|path=" + Sanitize(WideToUtf8(GetDebugLogPath().wstring())));
        }

        return {
            "ok|debug|" + std::string(enabled ? "1" : "0") + "|" + Sanitize(WideToUtf8(GetDebugLogPath().wstring())),
            0
        };
    }

    if (lower == "status") {
        return {GetStatus(), 0};
    }

    if (lower == "timeline") {
        return {GetTimeline(), 0};
    }

    if (lower == "stop") {
        std::lock_guard<std::mutex> lock(g_mutex);
        EnsureWorkerStartedLocked();
        g_commandSerial++;
        g_commandIsPlay = false;
        g_commandUrl.clear();
        g_pauseRequested = false;
        g_stage = PlaybackStage::Idle;
        g_lastError.clear();
        ResetTimelineState();
        ClearPendingSeekState();
        ClearPendingVolumeState();
        g_commandCv.notify_one();
        DebugLog("command|stop");
        return {"ok|stopped", 0};
    }

    if (lower == "play") {
        const std::string url = args.empty() ? std::string() : StripWrappingQuotes(args[0]);
        if (url.empty()) {
            return {"err|missing_argument|url", 1};
        }

        int volume = 70;
        if (args.size() >= 2) {
            std::int64_t parsedVolume = 70;
            if (!TryParseInt64Loose(args[1], &parsedVolume)) {
                return {"err|invalid_argument|volume", 2};
            }

            volume = static_cast<int>(std::clamp<std::int64_t>(parsedVolume, 0, 100));
        }

        volume = std::clamp(volume, 0, 100);

        {
            std::lock_guard<std::mutex> lock(g_mutex);
            EnsureWorkerStartedLocked();
            g_commandSerial++;
            g_commandIsPlay = true;
            g_commandUrl = url;
            g_commandVolume = volume;
            g_pauseRequested = false;
            g_stage = PlaybackStage::Resolving;
            g_lastError.clear();
            ResetTimelineState();
            ClearPendingSeekState();
            ClearPendingVolumeState();
        }

        g_commandCv.notify_one();
        DebugLog("command|play|volume=" + std::to_string(volume) + "|url=" + Sanitize(url));
        return {"ok|queued", 0};
    }

    if (lower == "title") {
        const std::string url = args.empty() ? std::string() : StripWrappingQuotes(args[0]);
        if (url.empty()) {
            return {"err|missing_argument|url", 1};
        }

        std::string title;
        std::string errorMessage;
        if (!ResolveTrackTitle(url, &title, &errorMessage)) {
            return {errorMessage.empty() ? "err|resolve_failed|title" : errorMessage, 2};
        }

        return {"ok|title|" + title, 0};
    }

    if (lower == "pause") {
        std::lock_guard<std::mutex> lock(g_mutex);
        EnsureWorkerStartedLocked();
        g_pauseRequested = true;
        if (g_stage == PlaybackStage::Playing) {
            g_stage = PlaybackStage::Paused;
        }
        DebugLog("command|pause");
        return {"ok|pause_requested", 0};
    }

    if (lower == "volume" || lower == "setvolume") {
        if (args.empty()) {
            return {"err|missing_argument|volume", 1};
        }

        std::int64_t parsedVolume = 0;
        if (!TryParseInt64Loose(args[0], &parsedVolume)) {
            return {"err|invalid_argument|volume", 2};
        }

        const int volume = static_cast<int>(std::clamp<std::int64_t>(parsedVolume, 0, 100));
        {
            std::lock_guard<std::mutex> lock(g_mutex);
            EnsureWorkerStartedLocked();
            if (!(g_stage == PlaybackStage::Playing || g_stage == PlaybackStage::Paused || g_stage == PlaybackStage::Resolving)) {
                return {"err|invalid_state|" + GetStageName(g_stage), 2};
            }

            g_commandVolume = volume;
            g_pendingVolume.store(volume);
        }

        DebugLog("command|volume|value=" + std::to_string(volume));
        return {"ok|volume_requested|" + std::to_string(volume), 0};
    }

    if (lower == "resume") {
        std::lock_guard<std::mutex> lock(g_mutex);
        EnsureWorkerStartedLocked();
        g_pauseRequested = false;
        if (g_stage == PlaybackStage::Paused) {
            g_stage = PlaybackStage::Playing;
        }
        DebugLog("command|resume");
        return {"ok|resume_requested", 0};
    }

    if (lower == "prefetch") {
        const std::string url = args.empty() ? std::string() : StripWrappingQuotes(args[0]);
        if (url.empty()) {
            return {"err|missing_argument|url", 1};
        }

        {
            std::lock_guard<std::mutex> lock(g_mutex);
            StartPrefetchLocked(url);
        }

        DebugLog("command|prefetch|url=" + Sanitize(url));
        return {"ok|prefetch_queued", 0};
    }

    if (lower == "warmup") {
        bool shouldStartWarmup = false;
        {
            std::lock_guard<std::mutex> lock(g_mutex);
            EnsureWorkerStartedLocked();
            if (!g_warmupCompleted && !g_warmupRequested) {
                g_warmupRequested = true;
                shouldStartWarmup = true;
            }
        }

        if (shouldStartWarmup) {
            std::thread(WarmupBackendAsync).detach();
        }

        DebugLog(std::string("command|warmup|") + (shouldStartWarmup ? "started" : "ready"));
        return {shouldStartWarmup ? "ok|warmup_started" : "ok|warmup_ready", 0};
    }

    if (lower == "seek") {
        if (args.empty()) {
            return {"err|missing_argument|position_ms", 1};
        }

        std::int64_t requestedMs = 0;
        if (!TryParseInt64Loose(args[0], &requestedMs)) {
            return {"err|invalid_argument|position_ms", 2};
        }

        requestedMs = ClampPositionMs(requestedMs);
        {
            std::lock_guard<std::mutex> lock(g_mutex);
            EnsureWorkerStartedLocked();
            if (!(g_stage == PlaybackStage::Playing || g_stage == PlaybackStage::Paused || g_stage == PlaybackStage::Resolving)) {
                return {"err|invalid_state|" + GetStageName(g_stage), 2};
            }

            const std::int64_t durationMs = g_timelineDurationMs.load();
            if (durationMs > 0) {
                requestedMs = std::min(requestedMs, durationMs);
            }

            g_pendingSeekMs.store(requestedMs);
        }

        DebugLog("command|seek|requestedMs=" + std::to_string(requestedMs));
        return {"ok|seek_requested|" + std::to_string(requestedMs), 0};
    }

    if (lower == "playlistload") {
        const std::string url = args.empty() ? std::string() : StripWrappingQuotes(args[0]);
        if (url.empty()) {
            return {"err|missing_argument|url", 1};
        }

        std::uint64_t token = 0;
        std::size_t count = 0;
        std::string playlistTitle;
        std::string errorMessage;
        if (!ResolvePlaylist(url, &token, &playlistTitle, &count, &errorMessage)) {
            return {errorMessage.empty() ? "err|resolve_failed|playlist" : errorMessage, 2};
        }

        return {
            "ok|playlistload|" + std::to_string(token) + "|" + std::to_string(count) + "|" + playlistTitle,
            0
        };
    }

    if (lower == "playlistitem") {
        if (args.size() < 2) {
            return {"err|missing_argument|token_or_index", 1};
        }

        std::uint64_t token = 0;
        int index = -1;
        if (!TryParseUInt64Strict(args[0], &token) || !TryParseIntStrict(args[1], &index)) {
            return {"err|invalid_argument|token_or_index", 2};
        }

        PlaylistEntry entry;
        if (!GetCachedPlaylistItem(token, index, &entry)) {
            return {"err|playlist_item_missing", 3};
        }

        return {"ok|playlistitem|" + entry.url + "|" + entry.title, 0};
    }

    return {"err|unknown_command|" + Sanitize(command), 3};
}

std::pair<std::string, std::vector<std::string>> ParseStringCommand(const std::string& input) {
    std::string trimmed = TrimWhitespace(input);

    if (trimmed.empty()) {
        return {"version", {}};
    }

    std::vector<std::string> parts;
    std::size_t start = 0;
    std::size_t pipe = trimmed.find('|');
    if (pipe != std::string::npos) {
        while (start <= trimmed.size()) {
            const std::size_t next = trimmed.find('|', start);
            if (next == std::string::npos) {
                parts.emplace_back(trimmed.substr(start));
                break;
            }

            parts.emplace_back(trimmed.substr(start, next - start));
            start = next + 1;
        }

        std::string command = parts.empty() ? "version" : parts.front();
        if (!parts.empty()) {
            parts.erase(parts.begin());
        }
        return {command, parts};
    }

    const std::size_t separator = trimmed.find(' ');
    if (separator == std::string::npos) {
        return {trimmed, {}};
    }

    return {trimmed.substr(0, separator), {trimmed.substr(separator + 1)}};
}

}  // namespace

BOOL APIENTRY DllMain(HMODULE module, DWORD reason, LPVOID reserved) {
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(module);
    } else if (reason == DLL_PROCESS_DETACH && reserved == nullptr) {
        {
            std::lock_guard<std::mutex> lock(g_mutex);
            g_shutdownRequested = true;
            g_commandCv.notify_one();
            g_prefetchCv.notify_all();
        }
    }

    return TRUE;
}

extern "C" __declspec(dllexport) void __stdcall RVExtensionVersion(char* output, int outputSize) {
    WriteOutput(output, outputSize, kVersion);
}

extern "C" __declspec(dllexport) void __stdcall RVExtension(char* output, int outputSize, const char* function) {
    try {
        if (!PinCurrentModule()) {
            WriteOutput(output, outputSize, "err|internal|module_pin_failed");
            return;
        }
        const auto payload = ParseStringCommand(function == nullptr ? std::string() : std::string(function));
        const auto result = HandleCommand(payload.first, payload.second);
        WriteOutput(output, outputSize, result.first);
    } catch (const std::exception&) {
        WriteOutput(output, outputSize, "err|internal|exception");
    } catch (...) {
        WriteOutput(output, outputSize, "err|internal|unknown");
    }
}

extern "C" __declspec(dllexport) int __stdcall RVExtensionArgs(char* output, int outputSize, const char* function, const char** args, int argCount) {
    try {
        if (!PinCurrentModule()) {
            WriteOutput(output, outputSize, "err|internal|module_pin_failed");
            return 4;
        }

        std::vector<std::string> values;
        if (args != nullptr && argCount > 0) {
            values.reserve(static_cast<std::size_t>(argCount));
            for (int index = 0; index < argCount; ++index) {
                values.emplace_back(args[index] == nullptr ? "" : args[index]);
            }
        }

        const auto result = HandleCommand(function == nullptr ? std::string() : std::string(function), values);
        WriteOutput(output, outputSize, result.first);
        return result.second;
    } catch (const std::exception&) {
        WriteOutput(output, outputSize, "err|internal|exception");
        return 4;
    } catch (...) {
        WriteOutput(output, outputSize, "err|internal|unknown");
        return 4;
    }
}
