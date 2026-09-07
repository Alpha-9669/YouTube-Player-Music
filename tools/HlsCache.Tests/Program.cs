using A3YT.Native;

var origin = new Uri("https://manifest.googlevideo.com/hls/master/index.m3u8");
var checks = 0;

void Check(bool condition, string name)
{
    if (!condition)
        throw new Exception("FAIL: " + name);
    checks++;
}

void Reject(Action action, string expected)
{
    try
    {
        action();
    }
    catch (InvalidOperationException ex) when (ex.Message == "hls_" + expected)
    {
        checks++;
        return;
    }

    throw new Exception("FAIL: Expected hls_" + expected);
}

var master = """
    #EXTM3U
    #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="233",NAME="Lower, bitrate",DEFAULT=YES,URI="low.m3u8"
    #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="234",NAME="Other language",DEFAULT=NO,URI="other.m3u8"
    #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="234",NAME="Original, audio",DEFAULT=YES,URI="../audio/index.m3u8?key=a,b"
    #EXT-X-STREAM-INF:BANDWIDTH=128000,AUDIO="234"
    video.m3u8
    """;
Check(HlsAudioCache.SelectAudioPlaylist(master, origin)?.AbsoluteUri ==
    "https://manifest.googlevideo.com/hls/audio/index.m3u8?key=a,b", "preferred default and quoted commas");
var media = """
    #EXTM3U
    #EXT-X-PLAYLIST-TYPE:VOD
    #EXT-X-KEY:METHOD=NONE
    #EXTINF:5.001,Title, with comma
    ../chunk/1.aac?x=a,b
    #EXTINF:2,
    https://rr1---example.googlevideo.com/chunk/2
    #EXT-X-ENDLIST
    """;
Check(HlsAudioCache.SelectAudioPlaylist(media, origin) is null, "media input detection");
var segments = HlsAudioCache.ParseMediaPlaylist(media, origin);
Check(segments.Count == 2 && segments[0].AbsoluteUri ==
    "https://manifest.googlevideo.com/hls/chunk/1.aac?x=a,b", "relative media URLs");
Reject(() => HlsAudioCache.ParseMediaPlaylist(media.Replace("METHOD=NONE", "METHOD=AES-128,URI=\"key\""), origin),
    "encrypted_audio_unsupported");
Reject(() => HlsAudioCache.ParseMediaPlaylist(media.Replace("#EXT-X-ENDLIST", ""), origin), "live_audio_unsupported");
Reject(() => HlsAudioCache.ParseMediaPlaylist(media.Replace("../chunk/1.aac?x=a,b", "https://youtube.com.evil.test/file"), origin),
    "untrusted_host");
Reject(() => HlsAudioCache.ParseMediaPlaylist(media.Replace("#EXTINF:2,", "#EXT-X-BYTERANGE:200@0\n#EXTINF:2,"), origin),
    "byterange_unsupported");
Reject(() => HlsAudioCache.ParseMediaPlaylist(media.Replace("#EXTINF:2,", "#EXT-X-MAP:URI=\"init\"\n#EXTINF:2,"), origin),
    "fragmented_audio_unsupported");
Reject(() => HlsAudioCache.ParseMediaPlaylist(media.Replace("#EXTINF:2,", "#EXTINF:NaN,"), origin),
    "invalid_segment_duration");
Reject(() => HlsAudioCache.ParseAttributes("NAME=\"unfinished"), "invalid_attributes");
Reject(() => HlsAudioCache.ParseAttributes("NAME=\"done\"garbage"), "invalid_attributes");
Reject(() => HlsAudioCache.ParseAttributes("TYPE=AUDIO,TYPE=VIDEO"), "invalid_attributes");
Reject(() => HlsAudioCache.SelectAudioPlaylist(master.Replace("\"234\"", "\"999\"").Replace("\"233\"", "\"888\""), origin),
    "audio_rendition_unavailable");
Reject(() => HlsAudioCache.SelectAudioPlaylist(master.Replace("#EXTM3U", "#EXTM3U\n#EXT-X-SESSION-KEY:METHOD=SAMPLE-AES,URI=\"key\""), origin),
    "encrypted_audio_unsupported");

// A minimum ADTS frame: valid header declaring eight bytes plus one payload byte.
byte[] adts = [0xFF, 0xF1, 0x50, 0x80, 0x01, 0x1F, 0xFC, 0x00];
HlsAudioCache.ValidatePackedAudio(adts);
checks++;
byte[] id3 = [(byte)'I', (byte)'D', (byte)'3', 3, 0, 0, 0, 0, 0, 1, 0];
HlsAudioCache.ValidatePackedAudio([.. id3, .. adts, .. id3, .. adts]);
checks++;
Reject(() => HlsAudioCache.ValidatePackedAudio("<!doctype html>"u8), "non_adts_audio");
Reject(() => HlsAudioCache.ValidatePackedAudio([0x47, 0x40, 0x00, 0x10, 0, 0, 0]), "non_adts_audio");
Reject(() => HlsAudioCache.ValidatePackedAudio(adts.AsSpan(0, 7)), "truncated_adts_frame");
Reject(() => HlsAudioCache.ValidatePackedAudio(id3.AsSpan(0, 10)), "truncated_id3_tag");
var badId3 = (byte[])id3.Clone();
badId3[9] = 0x80;
Reject(() => HlsAudioCache.ValidatePackedAudio(badId3), "invalid_id3_header");

// Capacity pressure must make space after rapid skips without deleting files
// still being handed from the managed resolver to the native player.
var now = new DateTime(2026, 9, 7, 12, 0, 0, DateTimeKind.Utc);
Check(HlsAudioCache.CanEvict(now, now.AddMinutes(-1), true), "pressure evicts recent idle track");
Check(!HlsAudioCache.CanEvict(now, now.AddMinutes(-1), false), "no pressure retains recent idle track");
Check(!HlsAudioCache.CanEvict(now, now.AddSeconds(-9), true), "pressure preserves native handoff grace");
Check(HlsAudioCache.CanEvict(now, now.AddSeconds(-10), true), "pressure grace boundary");
Check(!HlsAudioCache.CanEvict(now, now.AddHours(-23), false), "ordinary cleanup preserves TTL");
Check(HlsAudioCache.CanEvict(now, now.AddHours(-25), false), "ordinary cleanup removes expired file");
Check(!HlsAudioCache.CanEvict(now, now.AddSeconds(1), true), "future timestamp remains protected");

foreach (var file in args)
{
    HlsAudioCache.ValidatePackedAudio(File.ReadAllBytes(file));
    checks++;
    Console.WriteLine("Validated packed AAC fixture: " + Path.GetFileName(file));
}

Console.WriteLine($"Passed {checks} HLS cache parser/audio checks.");
