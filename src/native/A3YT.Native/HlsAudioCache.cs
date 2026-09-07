using System.Globalization;
using System.Net.Http;
using System.Text;

namespace A3YT.Native;

/// <summary>
/// Materializes YouTube's VOD packed-AAC HLS audio into a local file that MFPlay
/// can seek and play. No signed URL is persisted or included in an error.
/// </summary>
internal static class HlsAudioCache
{
    private const int MaxManifestBytes = 2 * 1024 * 1024;
    private const int MaxSegmentBytes = 4 * 1024 * 1024;
    private const long MaxCacheBytes = 256L * 1024 * 1024;
    private const int MaxCacheEntries = 16;
    private const int MaxSegments = 8192;
    private const int DownloadParallelism = 4;
    private static readonly TimeSpan CacheTtl = TimeSpan.FromHours(24);
    private static readonly TimeSpan RecentUseGrace = TimeSpan.FromMinutes(10);
    private static readonly TimeSpan PressureUseGrace = TimeSpan.FromSeconds(10);
    private static readonly SemaphoreSlim DownloadGate = new(1, 1);
    private static readonly object StateLock = new();
    private static readonly Dictionary<string, CacheEntry> Entries = new(StringComparer.Ordinal);
    private static readonly string CacheDirectory = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Arma 3", "A3YT", "audio-cache");

    private sealed class CacheEntry(string path, DateTime created)
    {
        public string Path { get; } = path;
        public DateTime Created { get; } = created;
        public DateTime LastUsed { get; set; } = created;
    }

    private readonly record struct DownloadedBody(byte[] Bytes, Uri FinalUri);
    private readonly record struct DiskEntry(string Path, long Length, DateTime LastUsed);

    public static bool TryGet(string videoId, out string path)
    {
        lock (StateLock)
        {
            if (Entries.TryGetValue(videoId, out var entry))
            {
                var now = DateTime.UtcNow;
                if (now - entry.Created < CacheTtl && File.Exists(entry.Path))
                {
                    entry.LastUsed = now;
                    path = entry.Path;
                    return true;
                }

                Entries.Remove(videoId);
            }
        }

        path = string.Empty;
        return false;
    }

    // Leave the file intact: MFPlay may still have it open for the current track.
    public static void Invalidate(string videoId)
    {
        lock (StateLock)
        {
            Entries.Remove(videoId);
        }
    }

    public static async Task<string> PrepareAsync(
        HttpClient http, string videoId, string manifestUrl, string userAgent, CancellationToken ct)
    {
        if (TryGet(videoId, out var cached))
            return cached;

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeout.CancelAfter(TimeSpan.FromSeconds(90));
        var token = timeout.Token;
        var entered = false;
        string? partialPath = null;
        string? completedPath = null;
        try
        {
            await DownloadGate.WaitAsync(token).ConfigureAwait(false);
            entered = true;
            if (TryGet(videoId, out cached))
                return cached;

            var manifestUri = ParseTrustedUri(manifestUrl);
            var manifest = await ReadManifestAsync(http, manifestUri, userAgent, token).ConfigureAwait(false);
            var playlistUri = SelectAudioPlaylist(manifest.Text, manifest.FinalUri);
            if (playlistUri is not null)
                manifest = await ReadManifestAsync(http, playlistUri, userAgent, token).ConfigureAwait(false);

            var segments = ParseMediaPlaylist(manifest.Text, manifest.FinalUri);
            Directory.CreateDirectory(CacheDirectory);
            EnsureCapacity(0, 1, null);
            var basename = "a3yt-" + Guid.NewGuid().ToString("N");
            partialPath = Path.Combine(CacheDirectory, basename + ".part");
            completedPath = Path.Combine(CacheDirectory, basename + ".aac");
            long totalBytes = 0;
            await using (var output = new FileStream(partialPath, FileMode.CreateNew, FileAccess.Write,
                FileShare.None, 128 * 1024, FileOptions.Asynchronous | FileOptions.SequentialScan))
            {
                for (var index = 0; index < segments.Count; index += DownloadParallelism)
                {
                    token.ThrowIfCancellationRequested();
                    var count = Math.Min(DownloadParallelism, segments.Count - index);
                    var tasks = new Task<DownloadedBody>[count];
                    for (var offset = 0; offset < count; offset++)
                        tasks[offset] = DownloadAsync(http, segments[index + offset], userAgent,
                            MaxSegmentBytes, token);

                    var batch = await Task.WhenAll(tasks).ConfigureAwait(false);
                    long batchBytes = 0;
                    foreach (var segment in batch)
                    {
                        ValidatePackedAudio(segment.Bytes);
                        batchBytes += segment.Bytes.Length;
                    }

                    if (totalBytes + batchBytes > MaxCacheBytes)
                        throw Error("audio_too_large");

                    EnsureCapacity(batchBytes, 0, partialPath);
                    foreach (var segment in batch)
                        await output.WriteAsync(segment.Bytes, token).ConfigureAwait(false);
                    totalBytes += batchBytes;
                    // Make the on-disk size observable to the next capacity check.
                    await output.FlushAsync(token).ConfigureAwait(false);
                }
            }

            token.ThrowIfCancellationRequested();
            File.Move(partialPath, completedPath);
            partialPath = null;
            lock (StateLock)
            {
                Entries[videoId] = new CacheEntry(completedPath, DateTime.UtcNow);
            }

            var result = completedPath;
            completedPath = null;
            return result;
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested)
        {
            throw Error("preparation_timeout");
        }
        catch (HttpRequestException)
        {
            throw Error("network_error");
        }
        catch (IOException)
        {
            throw Error("cache_io_error");
        }
        catch (UnauthorizedAccessException)
        {
            throw Error("cache_access_denied");
        }
        finally
        {
            if (partialPath is not null)
                TryDelete(partialPath);
            if (completedPath is not null)
                TryDelete(completedPath);
            if (entered)
                DownloadGate.Release();
        }
    }

    private static InvalidOperationException Error(string reason) => new("hls_" + reason);

    private static Uri ParseTrustedUri(string value)
    {
        if (!Uri.TryCreate(value, UriKind.Absolute, out var uri))
            throw Error("invalid_url");
        ValidateTrustedUri(uri);
        return uri;
    }

    private static void ValidateTrustedUri(Uri uri)
    {
        if (uri.Scheme != Uri.UriSchemeHttps || !uri.IsDefaultPort || uri.UserInfo.Length != 0 ||
            !(TrustedHost(uri.IdnHost, "googlevideo.com") || TrustedHost(uri.IdnHost, "youtube.com")))
            throw Error("untrusted_host");
    }

    private static bool TrustedHost(string host, string domain) =>
        host.Equals(domain, StringComparison.OrdinalIgnoreCase) ||
        host.EndsWith("." + domain, StringComparison.OrdinalIgnoreCase);

    private static Uri ResolveTrustedUri(Uri baseUri, string relative)
    {
        if (!Uri.TryCreate(baseUri, relative, out var uri))
            throw Error("invalid_url");
        ValidateTrustedUri(uri);
        return uri;
    }

    private static async Task<DownloadedBody> DownloadAsync(
        HttpClient http, Uri uri, string userAgent, int limit, CancellationToken ct)
    {
        ValidateTrustedUri(uri);
        using var request = new HttpRequestMessage(HttpMethod.Get, uri);
        request.Headers.TryAddWithoutValidation("User-Agent", userAgent);
        using var response = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, ct)
            .ConfigureAwait(false);
        var finalUri = response.RequestMessage?.RequestUri ?? uri;
        ValidateTrustedUri(finalUri);
        if (!response.IsSuccessStatusCode)
            throw Error("http_" + ((int)response.StatusCode).ToString(CultureInfo.InvariantCulture));
        if (response.Content.Headers.ContentLength is > 0 && response.Content.Headers.ContentLength > limit)
            throw Error("response_too_large");

        await using var input = await response.Content.ReadAsStreamAsync(ct).ConfigureAwait(false);
        using var body = new MemoryStream();
        var buffer = new byte[64 * 1024];
        while (true)
        {
            var read = await input.ReadAsync(buffer, ct).ConfigureAwait(false);
            if (read == 0)
                break;
            if (body.Length + read > limit)
                throw Error("response_too_large");
            body.Write(buffer, 0, read);
        }

        return new DownloadedBody(body.ToArray(), finalUri);
    }

    private static async Task<(string Text, Uri FinalUri)> ReadManifestAsync(
        HttpClient http, Uri uri, string userAgent, CancellationToken ct)
    {
        var body = await DownloadAsync(http, uri, userAgent, MaxManifestBytes, ct).ConfigureAwait(false);
        try
        {
            var text = new UTF8Encoding(false, true).GetString(body.Bytes);
            return (text, body.FinalUri);
        }
        catch (DecoderFallbackException)
        {
            throw Error("invalid_manifest_encoding");
        }
    }

    // null means this already is a media playlist rather than a master playlist.
    internal static Uri? SelectAudioPlaylist(string text, Uri baseUri)
    {
        var lines = ManifestLines(text);
        Uri? selected = null;
        var bestRank = int.MaxValue;
        var isMaster = false;
        foreach (var line in lines)
        {
            if (line.StartsWith("#EXT-X-SESSION-KEY:", StringComparison.Ordinal))
            {
                var key = ParseAttributes(line[19..]);
                if (!key.TryGetValue("METHOD", out var method) || method != "NONE")
                    throw Error("encrypted_audio_unsupported");
            }
            if (line.StartsWith("#EXT-X-STREAM-INF:", StringComparison.Ordinal))
                isMaster = true;
            if (!line.StartsWith("#EXT-X-MEDIA:", StringComparison.Ordinal))
                continue;
            isMaster = true;
            var attributes = ParseAttributes(line[13..]);
            if (!attributes.TryGetValue("TYPE", out var type) || type != "AUDIO" ||
                !attributes.TryGetValue("GROUP-ID", out var group) ||
                !attributes.TryGetValue("URI", out var uri))
                continue;
            var groupRank = group switch { "234" => 0, "233" => 2, _ => 100 };
            if (groupRank == 100)
                continue;
            var rank = groupRank + (attributes.TryGetValue("DEFAULT", out var isDefault) &&
                isDefault == "YES" ? 0 : 1);
            if (rank >= bestRank)
                continue;
            selected = ResolveTrustedUri(baseUri, uri);
            bestRank = rank;
        }

        if (isMaster && selected is null)
            throw Error("audio_rendition_unavailable");
        return selected;
    }

    internal static List<Uri> ParseMediaPlaylist(string text, Uri baseUri)
    {
        var lines = ManifestLines(text);
        var segments = new List<Uri>();
        var expectsSegment = false;
        var ended = false;
        foreach (var line in lines)
        {
            if (line.Length == 0)
                continue;
            if (line.StartsWith("#EXT-X-KEY:", StringComparison.Ordinal) ||
                line.StartsWith("#EXT-X-SESSION-KEY:", StringComparison.Ordinal))
            {
                var attributes = ParseAttributes(line[(line.IndexOf(':') + 1)..]);
                if (!attributes.TryGetValue("METHOD", out var method) || method != "NONE")
                    throw Error("encrypted_audio_unsupported");
            }
            else if (line.StartsWith("#EXT-X-BYTERANGE:", StringComparison.Ordinal))
                throw Error("byterange_unsupported");
            else if (line.StartsWith("#EXT-X-MAP:", StringComparison.Ordinal))
                throw Error("fragmented_audio_unsupported");
            else if (line.StartsWith("#EXT-X-STREAM-INF:", StringComparison.Ordinal) ||
                line.StartsWith("#EXT-X-MEDIA:", StringComparison.Ordinal))
                throw Error("nested_master_unsupported");
            else if (line.StartsWith("#EXTINF:", StringComparison.Ordinal))
            {
                if (expectsSegment || ended)
                    throw Error("invalid_media_playlist");
                var value = line[8..].Split(',', 2)[0];
                if (!double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out var duration) ||
                    !double.IsFinite(duration) || duration <= 0)
                    throw Error("invalid_segment_duration");
                expectsSegment = true;
            }
            else if (line == "#EXT-X-ENDLIST")
            {
                if (expectsSegment || ended)
                    throw Error("invalid_media_playlist");
                ended = true;
            }
            else if (!line.StartsWith('#'))
            {
                if (!expectsSegment || ended)
                    throw Error("invalid_media_playlist");
                if (segments.Count >= MaxSegments)
                    throw Error("too_many_segments");
                segments.Add(ResolveTrustedUri(baseUri, line));
                expectsSegment = false;
            }
        }

        if (!ended)
            throw Error("live_audio_unsupported");
        if (expectsSegment || segments.Count == 0)
            throw Error("empty_or_incomplete_playlist");
        return segments;
    }

    private static string[] ManifestLines(string text)
    {
        if (text.Length > MaxManifestBytes)
            throw Error("manifest_too_large");
        var lines = text.TrimStart('\uFEFF').Split('\n');
        for (var index = 0; index < lines.Length; index++)
            lines[index] = lines[index].Trim();
        if (lines.Length == 0 || lines[0] != "#EXTM3U")
            throw Error("invalid_manifest");
        return lines;
    }

    internal static Dictionary<string, string> ParseAttributes(string text)
    {
        var result = new Dictionary<string, string>(StringComparer.Ordinal);
        var position = 0;
        while (position < text.Length)
        {
            while (position < text.Length && char.IsWhiteSpace(text[position]))
                position++;
            var start = position;
            while (position < text.Length && text[position] != '=' && text[position] != ',')
                position++;
            if (position == text.Length || text[position] != '=')
                throw Error("invalid_attributes");
            var name = text[start..position].Trim();
            if (name.Length == 0)
                throw Error("invalid_attributes");
            position++;
            while (position < text.Length && char.IsWhiteSpace(text[position]))
                position++;
            string value;
            if (position < text.Length && text[position] == '"')
            {
                start = ++position;
                while (position < text.Length && text[position] != '"')
                    position++;
                if (position == text.Length)
                    throw Error("invalid_attributes");
                value = text[start..position++];
                while (position < text.Length && char.IsWhiteSpace(text[position]))
                    position++;
                if (position < text.Length && text[position] != ',')
                    throw Error("invalid_attributes");
            }
            else
            {
                start = position;
                while (position < text.Length && text[position] != ',')
                    position++;
                value = text[start..position].Trim();
            }

            if (value.Length == 0 || !result.TryAdd(name, value))
                throw Error("invalid_attributes");
            if (position < text.Length && ++position == text.Length)
                throw Error("invalid_attributes");
        }

        return result;
    }

    internal static void ValidatePackedAudio(ReadOnlySpan<byte> data)
    {
        var offset = 0;
        var frames = 0;
        while (offset < data.Length)
        {
            if (data.Length - offset >= 10 && data[offset] == 'I' && data[offset + 1] == 'D' &&
                data[offset + 2] == '3')
            {
                var header = data.Slice(offset, 10);
                if (header[3] is < 2 or > 4 || header[4] == 0xFF ||
                    (header[6] | header[7] | header[8] | header[9]) >= 0x80)
                    throw Error("invalid_id3_header");
                var size = (header[6] << 21) | (header[7] << 14) | (header[8] << 7) | header[9];
                var footer = header[3] == 4 && (header[5] & 0x10) != 0 ? 10 : 0;
                if (size > data.Length - offset - 10 - footer)
                    throw Error("truncated_id3_tag");
                offset += 10 + size + footer;
                continue;
            }

            // ADTS sync word, zero MPEG layer, and a defined sampling-frequency index.
            if (data.Length - offset < 7 || data[offset] != 0xFF ||
                (data[offset + 1] & 0xF6) != 0xF0 || ((data[offset + 2] >> 2) & 0x0F) >= 13)
                throw Error("non_adts_audio");
            var frameLength = ((data[offset + 3] & 3) << 11) |
                (data[offset + 4] << 3) | (data[offset + 5] >> 5);
            var headerLength = (data[offset + 1] & 1) == 0 ? 9 : 7;
            if (frameLength < headerLength || frameLength > data.Length - offset)
                throw Error("truncated_adts_frame");
            offset += frameLength;
            frames++;
        }

        if (frames == 0)
            throw Error("empty_audio_segment");
    }

    private static void EnsureCapacity(long additionalBytes, int additionalEntries, string? activePartial)
    {
        var now = DateTime.UtcNow;
        var diskEntries = new List<DiskEntry>();
        foreach (var path in Directory.EnumerateFiles(CacheDirectory, "a3yt-*", SearchOption.TopDirectoryOnly))
        {
            var name = Path.GetFileNameWithoutExtension(path);
            var extension = Path.GetExtension(path);
            if (name.Length != 37 || !Guid.TryParseExact(name[5..], "N", out _) ||
                !(extension == ".aac" || extension == ".part"))
                continue;
            try
            {
                var info = new FileInfo(path);
                var lastUsed = info.LastWriteTimeUtc;
                lock (StateLock)
                {
                    foreach (var entry in Entries.Values)
                    {
                        if (entry.Path == path && entry.LastUsed > lastUsed)
                            lastUsed = entry.LastUsed;
                    }
                }

                diskEntries.Add(new DiskEntry(path, info.Length, lastUsed));
            }
            catch (FileNotFoundException)
            {
                // Another process may be cleaning its own stale cache files.
            }
        }

        var bytes = diskEntries.Sum(entry => entry.Length);
        var count = diskEntries.Count;
        foreach (var entry in diskEntries.OrderBy(entry => entry.LastUsed))
        {
            var overCapacity = bytes + additionalBytes > MaxCacheBytes ||
                count + additionalEntries > MaxCacheEntries;
            if (entry.Path == activePartial || !CanEvict(now, entry.LastUsed, overCapacity))
                continue;
            lock (StateLock)
            {
                // TryGet can renew an entry while this directory scan is running.
                // Recheck under the same lock before removing the underlying file.
                if (Entries.Values.Any(cached => cached.Path == entry.Path &&
                    !CanEvict(now, cached.LastUsed, overCapacity)) || !TryDelete(entry.Path))
                    continue;
                bytes -= entry.Length;
                count--;
                foreach (var key in Entries.Where(pair => pair.Value.Path == entry.Path)
                    .Select(pair => pair.Key).ToArray())
                    Entries.Remove(key);
            }
        }

        if (bytes + additionalBytes > MaxCacheBytes || count + additionalEntries > MaxCacheEntries)
            throw Error("cache_full");
    }

    internal static bool CanEvict(DateTime now, DateTime lastUsed, bool underPressure)
    {
        var age = now - lastUsed;
        // Keep a short handoff window before native MFPlay acquires its read
        // lease. Under pressure, older idle files must not block rapid skips
        // for ten minutes; active playback remains protected by its file lease.
        var grace = underPressure ? PressureUseGrace : RecentUseGrace;
        return age >= grace && (underPressure || age > CacheTtl);
    }

    private static bool TryDelete(string path)
    {
        try
        {
            File.Delete(path);
            return true;
        }
        catch (IOException)
        {
            return false;
        }
        catch (UnauthorizedAccessException)
        {
            return false;
        }
    }
}
