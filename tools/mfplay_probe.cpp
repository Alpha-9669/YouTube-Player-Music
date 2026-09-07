#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <mfapi.h>
#include <mfplay.h>
#include <propvarutil.h>

#include <atomic>
#include <chrono>
#include <iomanip>
#include <iostream>
#include <mutex>
#include <thread>

namespace {
std::mutex outputMutex;
const auto startedAt = std::chrono::steady_clock::now();

long long ElapsedMs() {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now() - startedAt).count();
}

const char* EventName(MFP_EVENT_TYPE type) {
    switch (type) {
    case MFP_EVENT_TYPE_PLAY: return "play";
    case MFP_EVENT_TYPE_PAUSE: return "pause";
    case MFP_EVENT_TYPE_STOP: return "stop";
    case MFP_EVENT_TYPE_POSITION_SET: return "position_set";
    case MFP_EVENT_TYPE_MEDIAITEM_CREATED: return "item_created";
    case MFP_EVENT_TYPE_MEDIAITEM_SET: return "item_set";
    case MFP_EVENT_TYPE_PLAYBACK_ENDED: return "ended";
    case MFP_EVENT_TYPE_ERROR: return "error";
    default: return "other";
    }
}

class Callback final : public IMFPMediaPlayerCallback {
public:
    STDMETHODIMP QueryInterface(REFIID iid, void** output) override {
        if (output == nullptr) return E_POINTER;
        *output = nullptr;
        if (iid != __uuidof(IUnknown) && iid != __uuidof(IMFPMediaPlayerCallback)) return E_NOINTERFACE;
        *output = static_cast<IMFPMediaPlayerCallback*>(this);
        AddRef();
        return S_OK;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return ++references; }
    STDMETHODIMP_(ULONG) Release() override {
        const auto left = --references;
        if (left == 0) delete this;
        return left;
    }
    void STDMETHODCALLTYPE OnMediaPlayerEvent(MFP_EVENT_HEADER* event) override {
        if (event == nullptr) return;
        std::lock_guard<std::mutex> lock(outputMutex);
        std::cout << ElapsedMs() << "ms event=" << EventName(event->eEventType)
                  << " id=" << event->eEventType << " hr=0x" << std::hex
                  << static_cast<unsigned long>(event->hrEvent) << std::dec
                  << " state=" << event->eState << std::endl;
    }
private:
    std::atomic<ULONG> references{1};
};

long long ReadTime(IMFPMediaPlayer* player, bool duration, HRESULT* result) {
    PROPVARIANT value{};
    PropVariantInit(&value);
    *result = duration ? player->GetDuration(MFP_POSITIONTYPE_100NS, &value)
                       : player->GetPosition(MFP_POSITIONTYPE_100NS, &value);
    LONGLONG time = -10000;
    if (SUCCEEDED(*result)) PropVariantToInt64(value, &time);
    PropVariantClear(&value);
    return time / 10000;
}
}

int wmain(int argc, wchar_t** argv) {
    if (argc < 2) {
        std::cerr << "Usage: mfplay_probe.exe <local-path-or-url> [seconds=10] [seek-ms-after-1s] [pause-resume]\n";
        return 2;
    }
    const HRESULT comHr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    const HRESULT mfHr = MFStartup(MF_VERSION);
    if (FAILED(comHr) || FAILED(mfHr)) return 3;
    auto* callback = new Callback();
    IMFPMediaPlayer* player = nullptr;
    // Create stopped, set mute, then request playback; callbacks are never reset.
    const HRESULT createHr = MFPCreateMediaPlayer(argv[1], FALSE,
        MFP_OPTION_FREE_THREADED_CALLBACK | MFP_OPTION_NO_REMOTE_DESKTOP_OPTIMIZATION,
        callback, nullptr, &player);
    {
        std::lock_guard<std::mutex> lock(outputMutex);
        std::cout << ElapsedMs() << "ms create hr=0x" << std::hex
                  << static_cast<unsigned long>(createHr) << std::dec << std::endl;
    }
    if (SUCCEEDED(createHr) && player != nullptr) {
        const HRESULT volumeHr = player->SetVolume(0.0f);
        const HRESULT playHr = player->Play();
        {
            std::lock_guard<std::mutex> lock(outputMutex);
            std::cout << ElapsedMs() << "ms mute hr=0x" << std::hex
                      << static_cast<unsigned long>(volumeHr) << " play hr=0x"
                      << static_cast<unsigned long>(playHr) << std::dec << std::endl;
        }
        const int seconds = argc > 2 ? _wtoi(argv[2]) : 10;
        const auto playbackStart = std::chrono::steady_clock::now();
        const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(seconds);
        bool seekIssued = false;
        bool pauseIssued = false;
        bool resumeIssued = false;
        while (std::chrono::steady_clock::now() < deadline) {
            const auto elapsed = std::chrono::steady_clock::now() - playbackStart;
            if (argc > 4 && !pauseIssued && elapsed >= std::chrono::milliseconds(1500)) {
                const HRESULT pauseHr = player->Pause();
                pauseIssued = true;
                std::lock_guard<std::mutex> lock(outputMutex);
                std::cout << ElapsedMs() << "ms pause hr=0x" << std::hex
                          << static_cast<unsigned long>(pauseHr) << std::dec << std::endl;
            } else if (argc > 4 && pauseIssued && !resumeIssued && elapsed >= std::chrono::milliseconds(2500)) {
                const HRESULT resumeHr = player->Play();
                resumeIssued = true;
                std::lock_guard<std::mutex> lock(outputMutex);
                std::cout << ElapsedMs() << "ms resume hr=0x" << std::hex
                          << static_cast<unsigned long>(resumeHr) << std::dec << std::endl;
            }
            if (argc > 3 && !seekIssued &&
                elapsed >= std::chrono::seconds(1)) {
                PROPVARIANT target{};
                PropVariantInit(&target);
                target.vt = VT_I8;
                target.hVal.QuadPart = _wtoi64(argv[3]) * 10000;
                const HRESULT seekHr = player->SetPosition(MFP_POSITIONTYPE_100NS, &target);
                PropVariantClear(&target);
                seekIssued = true;
                std::lock_guard<std::mutex> lock(outputMutex);
                std::cout << ElapsedMs() << "ms seek hr=0x" << std::hex
                          << static_cast<unsigned long>(seekHr) << std::dec << std::endl;
            }
            HRESULT positionHr{}, durationHr{};
            const auto position = ReadTime(player, false, &positionHr);
            const auto duration = ReadTime(player, true, &durationHr);
            MFP_MEDIAPLAYER_STATE state = MFP_MEDIAPLAYER_STATE_EMPTY;
            const HRESULT stateHr = player->GetState(&state);
            {
                std::lock_guard<std::mutex> lock(outputMutex);
                std::cout << ElapsedMs() << "ms state=" << state << " positionMs=" << position
                          << " durationMs=" << duration << " hr=0x" << std::hex
                          << static_cast<unsigned long>(stateHr) << "/0x"
                          << static_cast<unsigned long>(positionHr) << "/0x"
                          << static_cast<unsigned long>(durationHr) << std::dec << std::endl;
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(500));
        }
        player->Stop();
        player->Shutdown();
        player->Release();
    }
    callback->Release();
    MFShutdown();
    CoUninitialize();
    return FAILED(createHr) ? 1 : 0;
}
