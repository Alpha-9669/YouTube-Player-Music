// Compile as a standalone Windows console test, linking the same Media Foundation
// libraries as the extension. Includes the real implementation to test its locks
// and command notifications without network access or audio playback.
#include "../src/extension/a3yt_player.cpp"

#include <future>
#include <iostream>
#include <stdexcept>

namespace {
std::atomic<int> resolverCalls{0};
extern "C" int __stdcall YPM0(const char*, char* output, int size) {
    ++resolverCalls;
    a3yt::WriteOutput(output, size, "err|unexpected_test_resolve");
    return 1;
}
extern "C" int __stdcall YPM1(const char*, char*, int) { return 1; }
extern "C" int __stdcall YPM2(char*, int) { return 1; }
extern "C" int __stdcall YPM3(const char*, char*, int) { return 1; }

void Check(bool condition, const char* description) {
    if (!condition) {
        std::cerr << "FAIL: " << description << '\n';
        std::exit(1);
    }
}

void Reset(bool running = false) {
    std::lock_guard<std::mutex> lock(g_mutex);
    g_shutdownRequested = false;
    g_commandSerial = 10;
    g_workerStarted = true; // Commands notify, but must not spawn an audio worker.
    g_prefetchSerial = 20;
    g_prefetchUrl = "track-a";
    g_prefetchRunning = running;
    g_prefetchWorkerActive = running;
    g_prefetchResolvedUrl.clear();
    g_prefetchError.clear();
    g_stage = PlaybackStage::Idle;
}

struct Result {
    PrefetchedResolveResult state;
    std::wstring url;
    std::string error;
};

Result Read(const std::string& input = "track-a", std::uint64_t command = 10) {
    Result result;
    result.state = TryUsePrefetchedResolve(input, command, &result.url, &result.error);
    return result;
}

auto BeginWait() {
    auto waiter = std::async(std::launch::async, [] { return Read(); });
    Check(waiter.wait_for(std::chrono::milliseconds(50)) == std::future_status::timeout,
          "pending prefetch should wait");
    return waiter;
}

Result FinishWait(std::future<Result>& waiter) {
    Check(waiter.wait_for(std::chrono::seconds(2)) == std::future_status::ready,
          "prefetch waiter should wake within two seconds");
    return waiter.get();
}
} // namespace

int main() {
    Reset();
    g_prefetchResolvedUrl = L"cached.aac";
    auto result = Read();
    Check(result.state == PrefetchedResolveResult::Ready && result.url == L"cached.aac", "ready cache");

    Reset();
    g_prefetchError = "resolver timed out";
    Check(Read("track-b").state == PrefetchedResolveResult::Missing, "other URL must not consume failure");
    Check(Read("track-a", 9).state == PrefetchedResolveResult::Superseded, "old command must not consume failure");
    result = Read();
    Check(result.state == PrefetchedResolveResult::Failed && result.error == "resolver timed out", "matching failure");
    Check(Read().state == PrefetchedResolveResult::Missing, "explicit retry gets a fresh attempt");

    Reset(true);
    auto failedWaiter = BeginWait();
    {
        std::lock_guard<std::mutex> lock(g_mutex);
        g_prefetchRunning = false;
        g_prefetchError = "download timed out";
        g_prefetchCv.notify_all();
    }
    result = FinishWait(failedWaiter);
    Check(result.state == PrefetchedResolveResult::Failed && result.error == "download timed out", "pending failure is propagated");

    Reset(true);
    auto replacedWaiter = BeginWait();
    {
        std::lock_guard<std::mutex> lock(g_mutex);
        StartPrefetchLocked("track-b");
    }
    Check(FinishWait(replacedWaiter).state == PrefetchedResolveResult::Missing, "prefetch replacement wakes waiter");

    Reset(true);
    auto newSerialWaiter = BeginWait();
    {
        std::lock_guard<std::mutex> lock(g_mutex);
        ++g_prefetchSerial;
        g_prefetchRunning = false;
        g_prefetchError = "new request failure";
        g_prefetchCv.notify_all();
    }
    Check(FinishWait(newSerialWaiter).state == PrefetchedResolveResult::Missing, "same URL, new serial is not consumed");
    Check(g_prefetchError == "new request failure", "replacement failure stays available to its own request");

    Reset(true);
    auto stoppedWaiter = BeginWait();
    HandleCommand("stop", {});
    Check(FinishWait(stoppedWaiter).state == PrefetchedResolveResult::Superseded, "stop wakes waiter");

    Reset(true);
    auto playWaiter = BeginWait();
    HandleCommand("play", {"track-b", "0"});
    Check(FinishWait(playWaiter).state == PrefetchedResolveResult::Superseded, "new play wakes waiter");

    Reset();
    g_prefetchError = "already timed out";
    g_commandIsPlay = true;
    g_commandUrl = "track-a";
    std::thread worker(WorkerMain);
    bool sawFailure = false;
    for (int i = 0; i < 200 && !sawFailure; ++i) {
        {
            std::lock_guard<std::mutex> lock(g_mutex);
            sawFailure = g_stage == PlaybackStage::Error;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    {
        std::lock_guard<std::mutex> lock(g_mutex);
        g_shutdownRequested = true;
        g_commandCv.notify_all();
        g_prefetchCv.notify_all();
    }
    worker.join();
    Check(sawFailure, "worker publishes prefetch failure");
    Check(resolverCalls.load() == 0, "worker must not perform a second full resolve after prefetch failure");
    std::cout << "PASS: prefetch result, failure retry, serial isolation, replacement, stop/play wakeups, worker timeout budget\n";
}
