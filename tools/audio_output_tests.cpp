#include "../src/extension/a3yt_player.cpp"
#include <audioclient.h>
#include <iostream>
#include <endpointvolume.h>
namespace {
std::string fixturePath;
extern "C" int __stdcall YPM0(const char*,char* output,int size){
 if(fixturePath.empty())return 1;
 return std::snprintf(output,static_cast<size_t>(size),"%s",fixturePath.c_str())>=size?1:0;
}
extern "C" int __stdcall YPM1(const char*,char*,int){return 1;}
extern "C" int __stdcall YPM2(char*,int){return 1;}
extern "C" int __stdcall YPM3(const char*,char*,int){return 1;}
void check(bool x,const char* m){std::cout<<(x?"PASS: ":"FAIL: ")<<m<<std::endl;if(!x)std::exit(1);}
void verifyVolume(PlayerHandle* p, float expected) {
 UINT32 count=0;check(SUCCEEDED(p->streamVolume->GetChannelCount(&count))&&count>0,"renderer channels ready");
 for(UINT32 i=0;i<count;++i){float actual=-1;check(SUCCEEDED(p->streamVolume->GetChannelVolume(i,&actual))&&std::abs(actual-expected)<0.0001f,"actual music channel gain");}
}
void tick(int ms){std::this_thread::sleep_for(std::chrono::milliseconds(ms));}
std::string command(const char* name, std::vector<const char*> args={}) {
 char output[4096]{};
 RVExtensionArgs(output,sizeof(output),name,args.data(),static_cast<int>(args.size()));
 return output;
}
bool waitStage(PlaybackStage expected) {
 for(int i=0;i<500;++i){
  {std::lock_guard<std::mutex> lock(g_mutex);if(g_stage==expected)return true;if(g_stage==PlaybackStage::Error)return false;}
  tick(10);
 }
 return false;
}
void requestVolume(const char* value) {
 check(command("volume",{value}).rfind("ok|volume_requested|",0)==0,"exported volume accepted");
 for(int i=0;i<100&&g_pendingVolume.load()!=-1;++i)tick(10);
 check(g_pendingVolume.load()==-1,"worker consumed volume request");
 tick(50);
}
}
int wmain(int argc,wchar_t** argv){
check(argc==2,"fixture supplied"); std::string error;
check(EnsurePlaybackBackendReady(&error),"MF ready");
PlayerHandle* p=nullptr;PlayerCallback* c=nullptr;
auto hr=StartPlayerFromUrl(argv[1],0,&p,&c);
std::cout<<HResultMessage("start",hr)<<std::endl;
check(SUCCEEDED(hr),"start with configured renderer");
verifyVolume(p,0.0f);
for(int v:{0,25,100,-10,150,0}){check(SetPlayerVolume(p,v),"change music volume");verifyVolume(p,static_cast<float>(std::clamp(v,0,100))/100.0f);}
tick(1300);auto pos=ReadPlayerPositionMs(p);tick(1000);
check(ReadPlayerPositionMs(p)>pos+500,"advancing timeline");
check(!a3yt::audio::SelectOutput().gameSession,"exclude own session");
check(PausePlayer(p),"pause");check(SetPlayerVolume(p,35),"volume while paused");verifyVolume(p,0.35f);check(SetPlayerVolume(p,0),"mute paused");tick(200);pos=ReadPlayerPositionMs(p);tick(400);
check(std::abs(ReadPlayerPositionMs(p)-pos)<100,"pause holds position");
check(SetPlayerPositionMs(p,120000)&&PlayPlayer(p),"seek and resume");tick(1000);
check(ReadPlayerPositionMs(p)>=120000,"seek advances");verifyVolume(p,0.0f);StopAndReleasePlayer(p);c->Release();
using Microsoft::WRL::ComPtr;
ComPtr<IMMDeviceEnumerator> e;check(SUCCEEDED(CoCreateInstance(__uuidof(MMDeviceEnumerator),nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&e))),"enumerate");
ComPtr<IMMDevice> d,chosen;check(SUCCEEDED(e->GetDefaultAudioEndpoint(eRender,eConsole,&d)),"default output");
auto defaultId=a3yt::audio::Describe(d.Get(),false).id;chosen=d;
ComPtr<IMMDeviceCollection> devices;e->EnumAudioEndpoints(eRender,DEVICE_STATE_ACTIVE,&devices);UINT count=0;devices->GetCount(&count);
for(UINT i=0;i<count;++i){ComPtr<IMMDevice> candidate;devices->Item(i,&candidate);if(a3yt::audio::Describe(candidate.Get(),false).id!=defaultId){chosen=candidate;break;}}
auto expected=a3yt::audio::Describe(chosen.Get(),true);
ComPtr<IAudioEndpointVolume> endpoint;
check(SUCCEEDED(chosen->Activate(__uuidof(IAudioEndpointVolume),CLSCTX_INPROC_SERVER,nullptr,reinterpret_cast<void**>(endpoint.GetAddressOf()))),"endpoint volume service");
float endpointBefore=0;BOOL endpointMuteBefore=FALSE;
endpoint->GetMasterVolumeLevelScalar(&endpointBefore);endpoint->GetMute(&endpointMuteBefore);
std::cout<<(expected.id!=defaultId?"TEST: non-default endpoint":"SKIP: only one physical output")<<std::endl;
ComPtr<IAudioClient> engine;check(SUCCEEDED(chosen->Activate(__uuidof(IAudioClient),CLSCTX_INPROC_SERVER,nullptr,reinterpret_cast<void**>(engine.GetAddressOf()))),"host engine");
WAVEFORMATEX* format=nullptr;engine->GetMixFormat(&format);
GUID engineId={0xec725fe1,0x7314,0x4e10,{0xab,0xc1,0xc4,0xc8,0x3f,0x1f,0x97,0x49}};
hr=engine->Initialize(AUDCLNT_SHAREMODE_SHARED,0,1000000,0,format,&engineId);CoTaskMemFree(format);check(SUCCEEDED(hr),"host session");
ComPtr<IAudioRenderClient> render;engine->GetService(IID_PPV_ARGS(&render));UINT32 frames=0;engine->GetBufferSize(&frames);BYTE* data=nullptr;
render->GetBuffer(frames,&data);render->ReleaseBuffer(frames,AUDCLNT_BUFFERFLAGS_SILENT);engine->Start();tick(200);
ComPtr<ISimpleAudioVolume> hostVolume;
check(SUCCEEDED(engine->GetService(IID_PPV_ARGS(&hostVolume))),"host volume service");
hostVolume->SetMasterVolume(0.43f,nullptr);hostVolume->SetMute(TRUE,nullptr);
auto selected=a3yt::audio::SelectOutput();check(selected.gameSession&&selected.id==expected.id,"detect host endpoint");
hr=StartPlayerFromUrl(argv[1],0,&p,&c);check(SUCCEEDED(hr)&&p->audioOutput.id==expected.id,"bind player to host endpoint");tick(1300);
check(ReadPlayerPositionMs(p)>500&&!c->SawError(),"host endpoint playback");
for(int v:{0,25,100,35,70,0}){
 check(SetPlayerVolume(p,v),"volume on host endpoint");verifyVolume(p,static_cast<float>(v)/100.0f);
 float hostActual=0,endpointActual=0;BOOL hostMute=FALSE,endpointMute=FALSE;
 hostVolume->GetMasterVolume(&hostActual);hostVolume->GetMute(&hostMute);
 endpoint->GetMasterVolumeLevelScalar(&endpointActual);endpoint->GetMute(&endpointMute);
 check(std::abs(hostActual-0.43f)<0.0001f&&hostMute,"game session volume/mute untouched");
 check(std::abs(endpointActual-endpointBefore)<0.0001f&&endpointMute==endpointMuteBefore,"endpoint volume/mute untouched");
}
check(RestartPlayerAtPosition(p,c,argv[1],0,120000,0,false),"production recovery restart succeeds");
verifyVolume(p,0.0f);check(p->audioOutput.id==expected.id,"restart retains host endpoint");tick(1300);
pos=ReadPlayerPositionMs(p);std::cout<<"restart position="<<pos<<" error="<<c->LastErrorMessage()<<std::endl;tick(1000);
check(pos>=119000&&ReadPlayerPositionMs(p)>pos+500&&!c->SawError(),"restart advances at target");StopAndReleasePlayer(p);c->Release();
hr=StartPlayerFromUrl(argv[1],70,&p,&c,false);check(SUCCEEDED(hr),"next track prepared without autoplay");verifyVolume(p,0.7f);
check(SetPlayerVolume(p,0)&&PlayPlayer(p),"next track starts muted");tick(300);verifyVolume(p,0.0f);
StopAndReleasePlayer(p);c->Release();engine->Stop();
fixturePath=WideToUtf8(std::filesystem::absolute(argv[1]).wstring());
check(command("play",{"https://www.youtube.com/watch?v=f50r2QKdkus","0"})=="ok|queued","exported play with offline resolver");
check(waitStage(PlaybackStage::Playing),"command worker starts real audio");
for(const char* value:{"0","25","100","35","50","0"})requestVolume(value);
check(command("volume",{"invalid"}).rfind("err|invalid_argument",0)==0,"reject invalid volume");
check(command("pause")=="ok|pause_requested"&&waitStage(PlaybackStage::Paused),"exported pause");
requestVolume("35");requestVolume("0");
check(command("resume")=="ok|resume_requested"&&waitStage(PlaybackStage::Playing),"exported resume");
check(command("stop")=="ok|stopped","exported stop");
check(command("volume",{"50"}).rfind("err|invalid_state",0)==0,"volume after stop rejected safely");
{std::lock_guard<std::mutex> lock(g_mutex);g_shutdownRequested=true;}g_commandCv.notify_all();tick(300);
}
