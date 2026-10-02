#pragma once
#include "extension_common.hpp"
#include <audiopolicy.h>
#include <mmdeviceapi.h>
#include <functiondiscoverykeys_devpkey.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfplay.h>
#include <mferror.h>
#include <wrl/client.h>

namespace a3yt::audio {
using Microsoft::WRL::ComPtr;
// A separate session identity prevents detecting our own music as the game.
inline constexpr GUID SessionId = {0x8b74d176,0xf206,0x436e,{0xb9,0x4a,0x23,0x65,0x32,0xa4,0x2c,0x87}};
struct Output { std::wstring id; std::wstring name; bool gameSession = false; };

inline Output Describe(IMMDevice* device, bool game) {
    Output out; out.gameSession = game;
    LPWSTR id = nullptr;
    if (SUCCEEDED(device->GetId(&id))) { out.id = id; CoTaskMemFree(id); }
    ComPtr<IPropertyStore> properties;
    PROPVARIANT value{};
    if (SUCCEEDED(device->OpenPropertyStore(STGM_READ, &properties)) &&
        SUCCEEDED(properties->GetValue(PKEY_Device_FriendlyName, &value)) && value.vt == VT_LPWSTR)
        out.name = value.pwszVal;
    PropVariantClear(&value);
    return out;
}

inline Output SelectOutput() {
    ComPtr<IMMDeviceEnumerator> enumerator;
    if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_INPROC_SERVER,
        IID_PPV_ARGS(&enumerator)))) return {};
    Output result;
    ComPtr<IMMDevice> defaultDevice;
    if (SUCCEEDED(enumerator->GetDefaultAudioEndpoint(eRender, eConsole, &defaultDevice)))
        result = Describe(defaultDevice.Get(), false);
    const auto defaultId = result.id;
    ComPtr<IMMDeviceCollection> devices;
    if (FAILED(enumerator->EnumAudioEndpoints(eRender, DEVICE_STATE_ACTIVE, &devices))) return result;
    UINT count = 0; devices->GetCount(&count);
    int bestScore = 0;
    for (UINT i = 0; i < count; ++i) {
        ComPtr<IMMDevice> device;
        ComPtr<IAudioSessionManager2> manager;
        if (FAILED(devices->Item(i, &device)) || FAILED(device->Activate(__uuidof(IAudioSessionManager2),
            CLSCTX_INPROC_SERVER, nullptr, reinterpret_cast<void**>(manager.GetAddressOf())))) continue;
        ComPtr<IAudioSessionControl> own;
        ComPtr<IAudioSessionControl2> own2;
        LPWSTR identifier = nullptr;
        std::wstring ownId;
        if (SUCCEEDED(manager->GetAudioSessionControl(&SessionId, 0, &own)) &&
            SUCCEEDED(own.As(&own2)) && SUCCEEDED(own2->GetSessionIdentifier(&identifier))) {
            ownId = identifier; CoTaskMemFree(identifier);
        }
        if (ownId.empty()) continue;
        ComPtr<IAudioSessionEnumerator> sessions;
        if (FAILED(manager->GetSessionEnumerator(&sessions))) continue;
        int sessionCount = 0; sessions->GetCount(&sessionCount);
        for (int j = 0; j < sessionCount; ++j) {
            ComPtr<IAudioSessionControl> control;
            ComPtr<IAudioSessionControl2> control2;
            DWORD pid = 0;
            AudioSessionState state = AudioSessionStateExpired;
            if (FAILED(sessions->GetSession(j, &control)) || FAILED(control.As(&control2)) ||
                FAILED(control2->GetProcessId(&pid)) || pid != GetCurrentProcessId() ||
                FAILED(control->GetState(&state)) || state == AudioSessionStateExpired) continue;
            identifier = nullptr;
            if (FAILED(control2->GetSessionIdentifier(&identifier))) continue;
            const bool ours = ownId == identifier;
            CoTaskMemFree(identifier);
            if (ours) continue;
            auto candidate = Describe(device.Get(), true);
            const int score = (state == AudioSessionStateActive ? 4 : 2) + (candidate.id == defaultId ? 1 : 0);
            if (score > bestScore && !candidate.id.empty()) { bestScore = score; result = candidate; }
        }
    }
    return result;
}

inline HRESULT Configure(IMFPMediaItem* item, const Output& output, IMFAudioStreamVolume** volume) {
    if (!volume) return E_POINTER;
    *volume = nullptr;
    ComPtr<IMFActivate> renderer;
    HRESULT hr = MFCreateAudioRendererActivate(&renderer);
    if (SUCCEEDED(hr) && !output.id.empty()) hr = renderer->SetString(MF_AUDIO_RENDERER_ATTRIBUTE_ENDPOINT_ID, output.id.c_str());
    if (SUCCEEDED(hr)) hr = renderer->SetGUID(MF_AUDIO_RENDERER_ATTRIBUTE_SESSION_ID, SessionId);
    DWORD count = 0;
    if (SUCCEEDED(hr)) hr = item->GetNumberOfStreams(&count);
    BOOL audio = FALSE, selected = FALSE;
    if (SUCCEEDED(hr)) hr = item->HasAudio(&audio, &selected);
    // The resolver deliberately supplies one audio-only stream.
    if (SUCCEEDED(hr) && (count != 1 || !audio || !selected)) return MF_E_INVALIDMEDIATYPE;
    ComPtr<IMFMediaSink> sink;
    ComPtr<IMFAudioStreamVolume> streamVolume;
    if (SUCCEEDED(hr)) hr = renderer->ActivateObject(IID_PPV_ARGS(&sink));
    if (SUCCEEDED(hr)) hr = MFGetService(sink.Get(), MR_STREAM_VOLUME_SERVICE, IID_PPV_ARGS(&streamVolume));
    if (SUCCEEDED(hr)) hr = item->SetStreamSink(0, renderer.Get());
    if (SUCCEEDED(hr)) *volume = streamVolume.Detach();
    else if (sink) sink->Shutdown();
    return hr;
}
}
