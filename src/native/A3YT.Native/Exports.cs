using System.Collections.Generic;
using System.Net;
using System.Net.Http;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace A3YT.Native;

public static partial class Exports
{
    private const string Version = "A3YTPlayer 0.5.3-backend";
    private static readonly string FallbackInnertubeApiKey = DecodeXorString(0x5A,
    [
        27, 19, 32, 59, 9, 35, 27, 21, 5, 28, 16, 104, 9, 54, 43, 15, 98, 11, 110, 9,
        14, 31, 18, 22, 29, 25, 51, 54, 45, 5, 3, 99, 5, 107, 107, 43, 57, 13, 98
    ]);
    private const int MaxStreamCacheEntries = 8;
    private const int MaxTitleCacheEntries = 64;
    private const char PlaylistMetaSeparator = '\u001D';
    private const char PlaylistRecordSeparator = '\u001E';
    private const char PlaylistFieldSeparator = '\u001F';
    private static readonly TimeSpan StreamCacheTtl = TimeSpan.FromMinutes(15);
    private static readonly TimeSpan TitleCacheTtl = TimeSpan.FromHours(6);
    private static readonly TimeSpan WatchContextCacheTtl = TimeSpan.FromHours(1);
    private static readonly Regex ApiKeyRegex = new("\"INNERTUBE_API_KEY\":\"([^\"]+)\"", RegexOptions.Compiled);
    private static readonly Regex ClientVersionRegex = new("\"INNERTUBE_CLIENT_VERSION\":\"([^\"]+)\"", RegexOptions.Compiled);
    private static readonly Regex VisitorDataRegex = new("\"visitorData\":\"([^\"]+)\"", RegexOptions.Compiled);
    private static readonly Lazy<HttpClient> Http = new(CreateHttpClient);
    private static readonly object StreamCacheLock = new();
    private static readonly object TitleCacheLock = new();
    private static readonly object WatchContextCacheLock = new();
    private static readonly YoutubeClientProfile[] ClientProfiles =
    [
        new("ANDROID_VR", "28", "1.60.19", "com.google.android.apps.youtube.vr.oculus/1.60.19 (Linux; U; Android 13; Quest 3; GB) gzip"),
        new("ANDROID", "3", "19.44.38", "com.google.android.youtube/19.44.38 (Linux; U; Android 13; Pixel 7 Pro Build/TQ3A.230805.001) gzip")
    ];

    private static readonly Dictionary<string, StreamCacheEntry> StreamCache = new(StringComparer.Ordinal);
    private static readonly Dictionary<string, TitleCacheEntry> TitleCache = new(StringComparer.Ordinal);
    private static string? CachedInnertubeApiKey;
    private static string? CachedVisitorData;
    private static DateTimeOffset CachedWatchContextUntilUtc = DateTimeOffset.MinValue;

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvStdcall)], EntryPoint = "YPM0")]
    public static unsafe int A3YTResolveAudioStreamUtf8(byte* input, byte* output, int outputSize)
    {
        return ResolveAudioStreamUtf8Core(input, output, outputSize);
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvStdcall)], EntryPoint = "YPM1")]
    public static unsafe int A3YTResolveTrackTitleUtf8(byte* input, byte* output, int outputSize)
    {
        try
        {
            var url = PtrToAnsi(input).Trim();
            if (string.IsNullOrWhiteSpace(url))
            {
                WriteUtf8Output(output, outputSize, "err|missing_argument|url");
                return 1;
            }

            var title = ResolveTrackTitleAsync(url).GetAwaiter().GetResult();
            WriteUtf8Output(output, outputSize, title);
            return 0;
        }
        catch (Exception ex)
        {
            WriteUtf8Output(output, outputSize, $"err|resolve_failed|{Sanitize(ex.Message)}");
            return 2;
        }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvStdcall)], EntryPoint = "YPM2")]
    public static unsafe int A3YTWarmupUtf8(byte* output, int outputSize)
    {
        try
        {
            WarmupAsync().GetAwaiter().GetResult();
            WriteUtf8Output(output, outputSize, "ok|warmup_ready");
            return 0;
        }
        catch (Exception ex)
        {
            WriteUtf8Output(output, outputSize, $"err|warmup_failed|{Sanitize(ex.Message)}");
            return 1;
        }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvStdcall)], EntryPoint = "YPM3")]
    public static unsafe int A3YTResolvePlaylistUtf8(byte* input, byte* output, int outputSize)
    {
        try
        {
            var url = PtrToAnsi(input).Trim();
            if (string.IsNullOrWhiteSpace(url))
            {
                WriteUtf8Output(output, outputSize, "err|missing_argument|url");
                return 1;
            }

            var playlist = ResolvePlaylistAsync(url).GetAwaiter().GetResult();
            WriteUtf8Output(output, outputSize, BuildPlaylistPayload(playlist));
            return 0;
        }
        catch (Exception ex)
        {
            WriteUtf8Output(output, outputSize, $"err|resolve_failed|{Sanitize(ex.Message)}");
            return 2;
        }
    }

    private static unsafe int ResolveAudioStreamUtf8Core(byte* input, byte* output, int outputSize)
    {
        try
        {
            var url = PtrToAnsi(input).Trim();
            if (string.IsNullOrWhiteSpace(url))
            {
                WriteUtf8Output(output, outputSize, "err|missing_argument|url");
                return 1;
            }

            var streamUrl = ResolveAudioStreamUrlAsync(url).GetAwaiter().GetResult();
            WriteUtf8Output(output, outputSize, streamUrl);
            return 0;
        }
        catch (Exception ex)
        {
            WriteUtf8Output(output, outputSize, $"err|resolve_failed|{Sanitize(ex.Message)}");
            return 2;
        }
    }

    private static async Task<string> ResolveAudioStreamUrlAsync(string input)
    {
        var normalizedInput = input.Trim();
        var videoId = ExtractVideoId(normalizedInput);
        if (string.IsNullOrWhiteSpace(videoId))
        {
            throw new InvalidOperationException("Could not parse YouTube URL.");
        }

        var cacheKey = "video:" + videoId;
        var cachedStreamUrl = TryGetCachedStreamUrl(cacheKey);
        if (!string.IsNullOrEmpty(cachedStreamUrl))
        {
            return cachedStreamUrl;
        }

        string? lastError = null;
        var cachedWatchContext = GetCachedWatchPageContext();
        Task<WatchPageContext?>? watchContextTask = cachedWatchContext is null
            ? FetchAndCacheWatchPageContextAsync(videoId, CancellationToken.None)
            : null;

        var streamUrl = await TryResolveAcrossProfilesAsync(clientProfile =>
            TryResolveAudioStreamUrlAsync(
                videoId,
                clientProfile,
                CancellationToken.None,
                cachedWatchContext?.ApiKey,
                cachedWatchContext?.VisitorData));
        if (!string.IsNullOrWhiteSpace(streamUrl))
        {
            RememberStreamUrl(cacheKey, streamUrl);
            return streamUrl;
        }

        var watchContext = watchContextTask is not null
            ? await watchContextTask
            : await FetchAndCacheWatchPageContextAsync(videoId, CancellationToken.None);

        if (watchContext is not null)
        {
            streamUrl = await TryResolveAcrossProfilesAsync(clientProfile =>
                TryResolveAudioStreamUrlAsync(videoId, clientProfile, CancellationToken.None, watchContext.ApiKey, watchContext.VisitorData));
            if (!string.IsNullOrWhiteSpace(streamUrl))
            {
                RememberStreamUrl(cacheKey, streamUrl);
                return streamUrl;
            }
        }

        lastError ??= "No playable audio stream found.";
        throw new InvalidOperationException(lastError);
    }

    private static async Task WarmupAsync()
    {
        _ = Http.Value;
        if (GetCachedWatchPageContext() is not null)
        {
            return;
        }

        var genericContext = await FetchGenericWatchPageContextAsync(CancellationToken.None);
        if (genericContext is not null)
        {
            CacheWatchPageContext(genericContext);
        }
    }

    private static async Task<string> ResolveTrackTitleAsync(string input)
    {
        var normalizedInput = input.Trim();
        var videoId = ExtractVideoId(normalizedInput);
        if (string.IsNullOrWhiteSpace(videoId))
        {
            throw new InvalidOperationException("Could not parse YouTube URL.");
        }

        var cachedTitle = TryGetCachedTitle(videoId);
        if (!string.IsNullOrWhiteSpace(cachedTitle))
        {
            return cachedTitle;
        }

        var cachedWatchContext = GetCachedWatchPageContext();
        Task<WatchPageContext?>? watchContextTask = cachedWatchContext is null
            ? FetchAndCacheWatchPageContextAsync(videoId, CancellationToken.None)
            : null;

        var title = await TryResolveAcrossProfilesAsync(clientProfile =>
            TryResolveTrackTitleAsync(
                videoId,
                clientProfile,
                CancellationToken.None,
                cachedWatchContext?.ApiKey,
                cachedWatchContext?.VisitorData));
        if (!string.IsNullOrWhiteSpace(title))
        {
            RememberTitle(videoId, title);
            return title;
        }

        var watchContext = watchContextTask is not null
            ? await watchContextTask
            : await FetchAndCacheWatchPageContextAsync(videoId, CancellationToken.None);

        if (watchContext is not null)
        {
            title = await TryResolveAcrossProfilesAsync(clientProfile =>
                TryResolveTrackTitleAsync(videoId, clientProfile, CancellationToken.None, watchContext.ApiKey, watchContext.VisitorData));
            if (!string.IsNullOrWhiteSpace(title))
            {
                RememberTitle(videoId, title);
                return title;
            }
        }

        throw new InvalidOperationException("Could not resolve track title.");
    }

    private static async Task<string?> TryResolveAcrossProfilesAsync(Func<YoutubeClientProfile, Task<string?>> resolver)
    {
        var tasks = new List<Task<string?>>(ClientProfiles.Length);
        foreach (var clientProfile in ClientProfiles)
        {
            tasks.Add(TryResolveProfileAsync(clientProfile, resolver));
        }

        while (tasks.Count > 0)
        {
            var completedTask = await Task.WhenAny(tasks);
            tasks.Remove(completedTask);

            var result = await completedTask;
            if (!string.IsNullOrWhiteSpace(result))
            {
                return result;
            }
        }

        return null;
    }

    private static async Task<string?> TryResolveProfileAsync(YoutubeClientProfile clientProfile, Func<YoutubeClientProfile, Task<string?>> resolver)
    {
        try
        {
            return await resolver(clientProfile);
        }
        catch
        {
            return null;
        }
    }

    private static async Task<PlaylistResult> ResolvePlaylistAsync(string input)
    {
        var playlistId = ExtractPlaylistId(input.Trim());
        if (string.IsNullOrWhiteSpace(playlistId))
        {
            throw new InvalidOperationException("Could not parse playlist URL.");
        }

        var playlistPageContext = await FetchPlaylistPageContextAsync(playlistId, CancellationToken.None);
        using var document = JsonDocument.Parse(playlistPageContext.InitialDataJson);
        var title = ExtractPlaylistTitle(document.RootElement, playlistId);
        var items = new List<PlaylistItem>();
        var seenVideoIds = new HashSet<string>(StringComparer.Ordinal);
        ExtractPlaylistItems(document.RootElement, playlistId, items, seenVideoIds);

        var continuationToken = ExtractPlaylistContinuationToken(document.RootElement);
        var apiKey = !string.IsNullOrWhiteSpace(playlistPageContext.ApiKey)
            ? playlistPageContext.ApiKey
            : GetCachedWatchPageContext()?.ApiKey ?? FallbackInnertubeApiKey;
        var visitorData = playlistPageContext.VisitorData ?? GetCachedWatchPageContext()?.VisitorData;
        var clientVersion = !string.IsNullOrWhiteSpace(playlistPageContext.ClientVersion)
            ? playlistPageContext.ClientVersion
            : "2.20240224.11.00";

        var continuationGuard = 0;
        while (!string.IsNullOrWhiteSpace(continuationToken) && continuationGuard < 32)
        {
            using var continuationDocument = await FetchPlaylistContinuationDocumentAsync(
                continuationToken,
                apiKey,
                visitorData,
                clientVersion,
                CancellationToken.None);

            ExtractPlaylistItems(continuationDocument.RootElement, playlistId, items, seenVideoIds);

            var nextToken = ExtractPlaylistContinuationToken(continuationDocument.RootElement);
            if (string.Equals(nextToken, continuationToken, StringComparison.Ordinal))
            {
                break;
            }

            continuationToken = nextToken;
            continuationGuard++;
        }

        if (items.Count == 0)
        {
            throw new InvalidOperationException("Playlist has no readable items.");
        }

        return new PlaylistResult(title, items);
    }

    private static async Task<string?> TryResolveAudioStreamUrlAsync(
        string videoId,
        YoutubeClientProfile clientProfile,
        CancellationToken cancellationToken,
        string? explicitApiKey = null,
        string? explicitVisitorData = null)
    {
        var cachedWatchContext = GetCachedWatchPageContext();
        var apiKey = explicitApiKey ?? cachedWatchContext?.ApiKey ?? FallbackInnertubeApiKey;
        var visitorData = explicitVisitorData ?? cachedWatchContext?.VisitorData;
        using var request = new HttpRequestMessage(HttpMethod.Post, $"https://www.youtube.com/youtubei/v1/player?key={Uri.EscapeDataString(apiKey)}&prettyPrint=false");
        request.Headers.TryAddWithoutValidation("Origin", "https://www.youtube.com");
        request.Headers.TryAddWithoutValidation("X-Youtube-Client-Name", clientProfile.HeaderName);
        request.Headers.TryAddWithoutValidation("X-Youtube-Client-Version", clientProfile.Version);
        request.Headers.TryAddWithoutValidation("User-Agent", clientProfile.UserAgent);
        if (!string.IsNullOrWhiteSpace(visitorData))
        {
            request.Headers.TryAddWithoutValidation("X-Goog-Visitor-Id", visitorData);
        }

        request.Content = new StringContent(BuildPlayerRequestBody(videoId, clientProfile, visitorData), Encoding.UTF8, "application/json");

        using var response = await Http.Value.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        var payload = await response.Content.ReadAsStringAsync(cancellationToken);

        if (!response.IsSuccessStatusCode)
        {
            return null;
        }

        using var document = JsonDocument.Parse(payload);
        if (TrySelectAudioUrl(document.RootElement, out var audioUrl))
        {
            return audioUrl;
        }

        return null;
    }

    private static async Task<string?> TryResolveTrackTitleAsync(
        string videoId,
        YoutubeClientProfile clientProfile,
        CancellationToken cancellationToken,
        string? explicitApiKey = null,
        string? explicitVisitorData = null)
    {
        var cachedWatchContext = GetCachedWatchPageContext();
        var apiKey = explicitApiKey ?? cachedWatchContext?.ApiKey ?? FallbackInnertubeApiKey;
        var visitorData = explicitVisitorData ?? cachedWatchContext?.VisitorData;
        using var request = new HttpRequestMessage(HttpMethod.Post, $"https://www.youtube.com/youtubei/v1/player?key={Uri.EscapeDataString(apiKey)}&prettyPrint=false");
        request.Headers.TryAddWithoutValidation("Origin", "https://www.youtube.com");
        request.Headers.TryAddWithoutValidation("X-Youtube-Client-Name", clientProfile.HeaderName);
        request.Headers.TryAddWithoutValidation("X-Youtube-Client-Version", clientProfile.Version);
        request.Headers.TryAddWithoutValidation("User-Agent", clientProfile.UserAgent);
        if (!string.IsNullOrWhiteSpace(visitorData))
        {
            request.Headers.TryAddWithoutValidation("X-Goog-Visitor-Id", visitorData);
        }

        request.Content = new StringContent(BuildPlayerRequestBody(videoId, clientProfile, visitorData), Encoding.UTF8, "application/json");

        using var response = await Http.Value.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        var payload = await response.Content.ReadAsStringAsync(cancellationToken);

        if (!response.IsSuccessStatusCode)
        {
            return null;
        }

        using var document = JsonDocument.Parse(payload);
        return TryExtractTitle(document.RootElement, out var title) ? title : null;
    }

    private static bool TrySelectAudioUrl(JsonElement root, out string audioUrl)
    {
        audioUrl = string.Empty;

        if (!root.TryGetProperty("streamingData", out var streamingData))
        {
            return false;
        }

        if (TrySelectAudioUrlFromFormats(streamingData, "adaptiveFormats", out audioUrl))
        {
            return true;
        }

        return TrySelectAudioUrlFromFormats(streamingData, "formats", out audioUrl);
    }

    private static bool TryExtractTitle(JsonElement root, out string title)
    {
        title = string.Empty;

        if (root.TryGetProperty("videoDetails", out var videoDetails) &&
            videoDetails.TryGetProperty("title", out var titleElement))
        {
            var candidate = titleElement.GetString();
            if (!string.IsNullOrWhiteSpace(candidate))
            {
                title = candidate;
                return true;
            }
        }

        if (root.TryGetProperty("microformat", out var microformat) &&
            microformat.TryGetProperty("playerMicroformatRenderer", out var renderer) &&
            renderer.TryGetProperty("title", out var titleObject) &&
            titleObject.TryGetProperty("simpleText", out var simpleText))
        {
            var candidate = simpleText.GetString();
            if (!string.IsNullOrWhiteSpace(candidate))
            {
                title = candidate;
                return true;
            }
        }

        return false;
    }

    private static async Task<PlaylistPageContext> FetchPlaylistPageContextAsync(string playlistId, CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, $"https://www.youtube.com/playlist?list={Uri.EscapeDataString(playlistId)}&hl=en");
        request.Headers.TryAddWithoutValidation("User-Agent", "Mozilla/5.0");
        request.Headers.TryAddWithoutValidation("Accept-Language", "en-US,en;q=0.9");

        using var response = await Http.Value.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            throw new InvalidOperationException($"Playlist page returned HTTP {(int)response.StatusCode}.");
        }

        var html = await response.Content.ReadAsStringAsync(cancellationToken);
        var initialDataJson = ExtractInitialDataJson(html);
        if (string.IsNullOrWhiteSpace(initialDataJson))
        {
            throw new InvalidOperationException("Could not extract playlist metadata.");
        }

        var apiKeyMatch = ApiKeyRegex.Match(html);
        var visitorDataMatch = VisitorDataRegex.Match(html);
        var clientVersionMatch = ClientVersionRegex.Match(html);

        return new PlaylistPageContext(
            initialDataJson,
            apiKeyMatch.Success ? apiKeyMatch.Groups[1].Value : null,
            visitorDataMatch.Success ? visitorDataMatch.Groups[1].Value : null,
            clientVersionMatch.Success ? clientVersionMatch.Groups[1].Value : null);
    }

    private static async Task<JsonDocument> FetchPlaylistContinuationDocumentAsync(
        string continuationToken,
        string apiKey,
        string? visitorData,
        string clientVersion,
        CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(
            HttpMethod.Post,
            $"https://www.youtube.com/youtubei/v1/browse?key={Uri.EscapeDataString(apiKey)}&prettyPrint=false");

        request.Headers.TryAddWithoutValidation("Origin", "https://www.youtube.com");
        request.Headers.TryAddWithoutValidation("X-Youtube-Client-Name", "1");
        request.Headers.TryAddWithoutValidation("X-Youtube-Client-Version", clientVersion);
        request.Headers.TryAddWithoutValidation("User-Agent", "Mozilla/5.0");
        if (!string.IsNullOrWhiteSpace(visitorData))
        {
            request.Headers.TryAddWithoutValidation("X-Goog-Visitor-Id", visitorData);
        }

        request.Content = new StringContent(
            BuildBrowseContinuationRequestBody(continuationToken, clientVersion, visitorData),
            Encoding.UTF8,
            "application/json");

        using var response = await Http.Value.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        var payload = await response.Content.ReadAsStringAsync(cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            throw new InvalidOperationException($"Playlist continuation returned HTTP {(int)response.StatusCode}.");
        }

        return JsonDocument.Parse(payload);
    }

    private static bool TrySelectAudioUrlFromFormats(JsonElement streamingData, string propertyName, out string audioUrl)
    {
        audioUrl = string.Empty;
        if (!streamingData.TryGetProperty(propertyName, out var formats) || formats.ValueKind != JsonValueKind.Array)
        {
            return false;
        }

        string? bestUrl = null;
        long bestBitrate = long.MaxValue;
        int bestPriority = int.MinValue;

        foreach (var format in formats.EnumerateArray())
        {
            if (!format.TryGetProperty("mimeType", out var mimeTypeElement))
            {
                continue;
            }

            var mimeType = mimeTypeElement.GetString() ?? string.Empty;
            if (!mimeType.StartsWith("audio/mp4", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            var directUrl = ExtractDirectUrl(format);
            if (string.IsNullOrWhiteSpace(directUrl))
            {
                continue;
            }

            var bitrate = format.TryGetProperty("bitrate", out var bitrateElement) && bitrateElement.TryGetInt64(out var parsedBitrate)
                ? parsedBitrate
                : 0;

            var itag = format.TryGetProperty("itag", out var itagElement) && itagElement.TryGetInt32(out var parsedItag)
                ? parsedItag
                : 0;

            var priority = itag == 139 ? 3 : (itag == 140 ? 2 : 1);
            if (priority > bestPriority || (priority == bestPriority && bitrate < bestBitrate))
            {
                bestPriority = priority;
                bestBitrate = bitrate;
                bestUrl = directUrl;
            }
        }

        if (string.IsNullOrWhiteSpace(bestUrl))
        {
            return false;
        }

        audioUrl = bestUrl;
        return true;
    }

    private static string? ExtractDirectUrl(JsonElement format)
    {
        if (format.TryGetProperty("url", out var urlElement))
        {
            return urlElement.GetString();
        }

        var cipher = format.TryGetProperty("signatureCipher", out var signatureCipherElement)
            ? signatureCipherElement.GetString()
            : format.TryGetProperty("cipher", out var cipherElement)
                ? cipherElement.GetString()
                : string.Empty;

        if (string.IsNullOrWhiteSpace(cipher))
        {
            return null;
        }

        var cipherUrl = GetQueryParameter(cipher, "url");
        var signature = GetQueryParameter(cipher, "sig");
        var signatureParameter = GetQueryParameter(cipher, "sp");

        if (string.IsNullOrWhiteSpace(cipherUrl))
        {
            return null;
        }

        if (!string.IsNullOrWhiteSpace(signature) && !string.IsNullOrWhiteSpace(signatureParameter))
        {
            var separator = cipherUrl.Contains('?') ? "&" : "?";
            return $"{cipherUrl}{separator}{Uri.EscapeDataString(signatureParameter)}={Uri.EscapeDataString(signature)}";
        }

        return cipherUrl;
    }

    private static string BuildPlayerRequestBody(string videoId, YoutubeClientProfile clientProfile, string? visitorData)
    {
        var visitorJson = string.IsNullOrWhiteSpace(visitorData)
            ? string.Empty
            : ",\"visitorData\":\"" + visitorData + "\"";

        return
            "{\"videoId\":\"" + videoId +
            "\",\"contentCheckOk\":true,\"racyCheckOk\":true,\"context\":{\"client\":{\"clientName\":\"" + clientProfile.ClientName +
            "\",\"clientVersion\":\"" + clientProfile.Version +
            "\",\"hl\":\"en\",\"gl\":\"US\",\"platform\":\"MOBILE\",\"osName\":\"Android\",\"osVersion\":\"13\",\"androidSdkVersion\":33" +
            visitorJson +
            "}}}";
    }

    private static string BuildBrowseContinuationRequestBody(string continuationToken, string clientVersion, string? visitorData)
    {
        var visitorJson = string.IsNullOrWhiteSpace(visitorData)
            ? string.Empty
            : ",\"visitorData\":\"" + visitorData + "\"";

        return
            "{\"context\":{\"client\":{\"clientName\":\"WEB\"" +
            ",\"clientVersion\":\"" + clientVersion +
            "\",\"hl\":\"en\",\"gl\":\"US\"" +
            visitorJson +
            "}},\"continuation\":\"" + continuationToken + "\"}";
    }

    private static string BuildPlaylistPayload(PlaylistResult playlist)
    {
        var builder = new StringBuilder(Math.Max(256, playlist.Items.Count * 80));
        builder.Append(SanitizePlaylistField(playlist.Title));
        builder.Append(PlaylistMetaSeparator);

        for (var index = 0; index < playlist.Items.Count; index++)
        {
            var item = playlist.Items[index];
            if (index > 0)
            {
                builder.Append(PlaylistRecordSeparator);
            }

            builder.Append(SanitizePlaylistField(item.Url));
            builder.Append(PlaylistFieldSeparator);
            builder.Append(SanitizePlaylistField(item.Title));
        }

        return builder.ToString();
    }

    private static HttpClient CreateHttpClient()
    {
        var handler = new HttpClientHandler
        {
            AutomaticDecompression = DecompressionMethods.All,
            UseCookies = false
        };

        return new HttpClient(handler)
        {
            Timeout = TimeSpan.FromSeconds(20)
        };
    }

    private static string? ExtractVideoId(string input)
    {
        if (string.IsNullOrWhiteSpace(input))
        {
            return null;
        }

        var trimmed = input.Trim();
        if (trimmed.Length == 11 && Regex.IsMatch(trimmed, "^[A-Za-z0-9_-]{11}$"))
        {
            return trimmed;
        }

        if (!Uri.TryCreate(trimmed, UriKind.Absolute, out var uri))
        {
            return null;
        }

        var host = uri.Host.ToLowerInvariant();
        if (host.EndsWith("youtu.be", StringComparison.Ordinal))
        {
            var path = uri.AbsolutePath.Trim('/');
            return string.IsNullOrWhiteSpace(path) ? null : path.Split('/')[0];
        }

        if (!host.Contains("youtube.com", StringComparison.Ordinal))
        {
            return null;
        }

        var directVideoId = GetQueryParameter(uri.Query.TrimStart('?'), "v");
        if (!string.IsNullOrWhiteSpace(directVideoId))
        {
            return directVideoId;
        }

        var segments = uri.AbsolutePath.Trim('/').Split('/', StringSplitOptions.RemoveEmptyEntries);
        if (segments.Length >= 2 && (segments[0].Equals("shorts", StringComparison.OrdinalIgnoreCase) ||
                                     segments[0].Equals("live", StringComparison.OrdinalIgnoreCase) ||
                                     segments[0].Equals("embed", StringComparison.OrdinalIgnoreCase)))
        {
            return segments[1];
        }

        return null;
    }

    private static string? ExtractPlaylistId(string input)
    {
        if (string.IsNullOrWhiteSpace(input))
        {
            return null;
        }

        var trimmed = input.Trim();
        if (!trimmed.Contains("://", StringComparison.Ordinal) && trimmed.Length >= 10)
        {
            return trimmed;
        }

        if (!Uri.TryCreate(trimmed, UriKind.Absolute, out var uri))
        {
            return null;
        }

        return GetQueryParameter(uri.Query.TrimStart('?'), "list");
    }

    private static string? GetQueryParameter(string query, string key)
    {
        if (string.IsNullOrWhiteSpace(query) || string.IsNullOrWhiteSpace(key))
        {
            return null;
        }

        foreach (var segment in query.Split('&', StringSplitOptions.RemoveEmptyEntries))
        {
            var separatorIndex = segment.IndexOf('=');
            if (separatorIndex <= 0)
            {
                continue;
            }

            var segmentKey = Uri.UnescapeDataString(segment[..separatorIndex]);
            if (!segmentKey.Equals(key, StringComparison.Ordinal))
            {
                continue;
            }

            return Uri.UnescapeDataString(segment[(separatorIndex + 1)..]);
        }

        return null;
    }

    private static string? ExtractInitialDataJson(string html)
    {
        if (string.IsNullOrWhiteSpace(html))
        {
            return null;
        }

        foreach (var marker in new[] { "var ytInitialData = ", "window[\"ytInitialData\"] = ", "ytInitialData = " })
        {
            var markerIndex = html.IndexOf(marker, StringComparison.Ordinal);
            if (markerIndex < 0)
            {
                continue;
            }

            var start = html.IndexOf('{', markerIndex + marker.Length);
            if (start < 0)
            {
                continue;
            }

            var depth = 0;
            var inString = false;
            var escaping = false;
            for (var index = start; index < html.Length; index++)
            {
                var ch = html[index];
                if (inString)
                {
                    if (escaping)
                    {
                        escaping = false;
                    }
                    else if (ch == '\\')
                    {
                        escaping = true;
                    }
                    else if (ch == '"')
                    {
                        inString = false;
                    }

                    continue;
                }

                if (ch == '"')
                {
                    inString = true;
                    continue;
                }

                if (ch == '{')
                {
                    depth++;
                    continue;
                }

                if (ch != '}')
                {
                    continue;
                }

                depth--;
                if (depth == 0)
                {
                    return html[start..(index + 1)];
                }
            }
        }

        return null;
    }

    private static string ExtractPlaylistTitle(JsonElement root, string playlistId)
    {
        if (TryExtractPlaylistTitle(root, out var title))
        {
            return title;
        }

        return "Playlist " + playlistId;
    }

    private static bool TryExtractPlaylistTitle(JsonElement element, out string title)
    {
        title = string.Empty;
        if (element.ValueKind == JsonValueKind.Object)
        {
            if (element.TryGetProperty("playlistMetadataRenderer", out var metadataRenderer))
            {
                var candidate = TryGetText(metadataRenderer, "title");
                if (!string.IsNullOrWhiteSpace(candidate))
                {
                    title = candidate;
                    return true;
                }
            }

            if (element.TryGetProperty("playlistHeaderRenderer", out var headerRenderer))
            {
                var candidate = TryGetText(headerRenderer, "title");
                if (!string.IsNullOrWhiteSpace(candidate))
                {
                    title = candidate;
                    return true;
                }
            }

            foreach (var property in element.EnumerateObject())
            {
                if (TryExtractPlaylistTitle(property.Value, out title))
                {
                    return true;
                }
            }
        }
        else if (element.ValueKind == JsonValueKind.Array)
        {
            foreach (var item in element.EnumerateArray())
            {
                if (TryExtractPlaylistTitle(item, out title))
                {
                    return true;
                }
            }
        }

        return false;
    }

    private static void ExtractPlaylistItems(JsonElement root, string playlistId, List<PlaylistItem> items, HashSet<string> seenVideoIds)
    {
        VisitJson(root, element =>
        {
            if (element.ValueKind != JsonValueKind.Object)
            {
                return;
            }

            if (element.TryGetProperty("playlistVideoRenderer", out var playlistRenderer))
            {
                TryAddPlaylistItem(items, seenVideoIds, playlistRenderer, playlistId);
                return;
            }

            if (element.TryGetProperty("playlistPanelVideoRenderer", out var playlistPanelRenderer))
            {
                TryAddPlaylistItem(items, seenVideoIds, playlistPanelRenderer, playlistId);
            }
        });
    }

    private static void TryAddPlaylistItem(List<PlaylistItem> items, HashSet<string> seenVideoIds, JsonElement renderer, string playlistId)
    {
        if (!renderer.TryGetProperty("videoId", out var videoIdElement))
        {
            return;
        }

        var videoId = videoIdElement.GetString();
        if (string.IsNullOrWhiteSpace(videoId) || !seenVideoIds.Add(videoId))
        {
            return;
        }

        var title = TryGetText(renderer, "title");
        if (string.IsNullOrWhiteSpace(title))
        {
            title = videoId;
        }

        items.Add(new PlaylistItem(
            $"https://www.youtube.com/watch?v={Uri.EscapeDataString(videoId)}&list={Uri.EscapeDataString(playlistId)}",
            title));
    }

    private static string? ExtractPlaylistContinuationToken(JsonElement root)
    {
        if (root.ValueKind == JsonValueKind.Object)
        {
            if (root.TryGetProperty("continuationItemRenderer", out var continuationItemRenderer))
            {
                var continuationToken = TryExtractContinuationTokenFromObject(continuationItemRenderer);
                if (!string.IsNullOrWhiteSpace(continuationToken))
                {
                    return continuationToken;
                }
            }

            var directToken = TryExtractContinuationTokenFromObject(root);
            if (!string.IsNullOrWhiteSpace(directToken))
            {
                return directToken;
            }

            foreach (var property in root.EnumerateObject())
            {
                var nestedToken = ExtractPlaylistContinuationToken(property.Value);
                if (!string.IsNullOrWhiteSpace(nestedToken))
                {
                    return nestedToken;
                }
            }
        }
        else if (root.ValueKind == JsonValueKind.Array)
        {
            foreach (var item in root.EnumerateArray())
            {
                var nestedToken = ExtractPlaylistContinuationToken(item);
                if (!string.IsNullOrWhiteSpace(nestedToken))
                {
                    return nestedToken;
                }
            }
        }

        return null;
    }

    private static string? TryExtractContinuationTokenFromObject(JsonElement element)
    {
        if (element.ValueKind != JsonValueKind.Object)
        {
            return null;
        }

        if (element.TryGetProperty("continuationEndpoint", out var continuationEndpoint))
        {
            var endpointToken = TryExtractContinuationTokenFromObject(continuationEndpoint);
            if (!string.IsNullOrWhiteSpace(endpointToken))
            {
                return endpointToken;
            }
        }

        if (element.TryGetProperty("continuationCommand", out var continuationCommand) &&
            continuationCommand.ValueKind == JsonValueKind.Object &&
            continuationCommand.TryGetProperty("token", out var tokenElement))
        {
            var token = tokenElement.GetString();
            if (!string.IsNullOrWhiteSpace(token))
            {
                return token;
            }
        }

        if (element.TryGetProperty("nextContinuationData", out var nextContinuationData) &&
            nextContinuationData.ValueKind == JsonValueKind.Object &&
            nextContinuationData.TryGetProperty("continuation", out var continuationElement))
        {
            var token = continuationElement.GetString();
            if (!string.IsNullOrWhiteSpace(token))
            {
                return token;
            }
        }

        if (element.TryGetProperty("continuations", out var continuations) && continuations.ValueKind == JsonValueKind.Array)
        {
            foreach (var continuation in continuations.EnumerateArray())
            {
                var token = TryExtractContinuationTokenFromObject(continuation);
                if (!string.IsNullOrWhiteSpace(token))
                {
                    return token;
                }
            }
        }

        return null;
    }

    private static void VisitJson(JsonElement element, Action<JsonElement> visitor)
    {
        visitor(element);

        switch (element.ValueKind)
        {
            case JsonValueKind.Object:
                foreach (var property in element.EnumerateObject())
                {
                    VisitJson(property.Value, visitor);
                }
                break;

            case JsonValueKind.Array:
                foreach (var item in element.EnumerateArray())
                {
                    VisitJson(item, visitor);
                }
                break;
        }
    }

    private static string? TryGetText(JsonElement element, string propertyName)
    {
        if (!element.TryGetProperty(propertyName, out var value))
        {
            return null;
        }

        if (value.ValueKind == JsonValueKind.String)
        {
            var text = value.GetString();
            return string.IsNullOrWhiteSpace(text) ? null : text.Trim();
        }

        if (value.ValueKind != JsonValueKind.Object)
        {
            return null;
        }

        if (value.TryGetProperty("simpleText", out var simpleText))
        {
            var text = simpleText.GetString();
            return string.IsNullOrWhiteSpace(text) ? null : text.Trim();
        }

        if (!value.TryGetProperty("runs", out var runs) || runs.ValueKind != JsonValueKind.Array)
        {
            return null;
        }

        var builder = new StringBuilder();
        foreach (var run in runs.EnumerateArray())
        {
            if (!run.TryGetProperty("text", out var textElement))
            {
                continue;
            }

            var text = textElement.GetString();
            if (string.IsNullOrWhiteSpace(text))
            {
                continue;
            }

            builder.Append(text);
        }

        return builder.Length == 0 ? null : builder.ToString().Trim();
    }

    private static WatchPageContext? GetCachedWatchPageContext()
    {
        lock (WatchContextCacheLock)
        {
            if (DateTimeOffset.UtcNow >= CachedWatchContextUntilUtc || string.IsNullOrWhiteSpace(CachedInnertubeApiKey))
            {
                CachedInnertubeApiKey = null;
                CachedVisitorData = null;
                CachedWatchContextUntilUtc = DateTimeOffset.MinValue;
                return null;
            }

            return new WatchPageContext(CachedInnertubeApiKey, CachedVisitorData);
        }
    }

    private static void CacheWatchPageContext(WatchPageContext watchPageContext)
    {
        lock (WatchContextCacheLock)
        {
            CachedInnertubeApiKey = watchPageContext.ApiKey;
            CachedVisitorData = watchPageContext.VisitorData;
            CachedWatchContextUntilUtc = DateTimeOffset.UtcNow.Add(WatchContextCacheTtl);
        }
    }

    private static async Task<WatchPageContext?> FetchWatchPageContextAsync(string videoId, CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, $"https://www.youtube.com/watch?v={Uri.EscapeDataString(videoId)}&hl=en");
        request.Headers.TryAddWithoutValidation("User-Agent", "Mozilla/5.0");

        using var response = await Http.Value.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            return null;
        }

        var html = await response.Content.ReadAsStringAsync(cancellationToken);
        var apiKeyMatch = ApiKeyRegex.Match(html);
        if (!apiKeyMatch.Success)
        {
            return null;
        }

        var visitorDataMatch = VisitorDataRegex.Match(html);
        var visitorData = visitorDataMatch.Success ? visitorDataMatch.Groups[1].Value : null;
        return new WatchPageContext(apiKeyMatch.Groups[1].Value, visitorData);
    }

    private static async Task<WatchPageContext?> FetchAndCacheWatchPageContextAsync(string videoId, CancellationToken cancellationToken)
    {
        try
        {
            var watchContext = await FetchWatchPageContextAsync(videoId, cancellationToken);
            if (watchContext is not null)
            {
                CacheWatchPageContext(watchContext);
            }

            return watchContext;
        }
        catch
        {
            return null;
        }
    }

    private static async Task<WatchPageContext?> FetchGenericWatchPageContextAsync(CancellationToken cancellationToken)
    {
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, "https://www.youtube.com/?hl=en");
            request.Headers.TryAddWithoutValidation("User-Agent", "Mozilla/5.0");

            using var response = await Http.Value.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
            if (!response.IsSuccessStatusCode)
            {
                return null;
            }

            var html = await response.Content.ReadAsStringAsync(cancellationToken);
            var apiKeyMatch = ApiKeyRegex.Match(html);
            if (!apiKeyMatch.Success)
            {
                return null;
            }

            var visitorDataMatch = VisitorDataRegex.Match(html);
            var visitorData = visitorDataMatch.Success ? visitorDataMatch.Groups[1].Value : null;
            return new WatchPageContext(apiKeyMatch.Groups[1].Value, visitorData);
        }
        catch
        {
            return null;
        }
    }

    private static string? TryGetCachedStreamUrl(string input)
    {
        lock (StreamCacheLock)
        {
            PruneExpiredStreamCacheEntriesLocked();

            if (!StreamCache.TryGetValue(input, out var entry))
            {
                return null;
            }

            if (string.IsNullOrWhiteSpace(entry.StreamUrl))
            {
                StreamCache.Remove(input);
                return null;
            }

            return entry.StreamUrl;
        }
    }

    private static string? TryGetCachedTitle(string videoId)
    {
        lock (TitleCacheLock)
        {
            PruneExpiredTitleCacheEntriesLocked();

            if (!TitleCache.TryGetValue(videoId, out var entry))
            {
                return null;
            }

            if (string.IsNullOrWhiteSpace(entry.Title))
            {
                TitleCache.Remove(videoId);
                return null;
            }

            return entry.Title;
        }
    }

    private static void RememberStreamUrl(string input, string streamUrl)
    {
        lock (StreamCacheLock)
        {
            PruneExpiredStreamCacheEntriesLocked();
            StreamCache[input] = new StreamCacheEntry(streamUrl, DateTimeOffset.UtcNow.Add(StreamCacheTtl));

            if (StreamCache.Count <= MaxStreamCacheEntries)
            {
                return;
            }

            string? oldestKey = null;
            var oldestExpiry = DateTimeOffset.MaxValue;
            foreach (var pair in StreamCache)
            {
                if (pair.Value.ExpiresUtc >= oldestExpiry)
                {
                    continue;
                }

                oldestKey = pair.Key;
                oldestExpiry = pair.Value.ExpiresUtc;
            }

            if (!string.IsNullOrWhiteSpace(oldestKey))
            {
                StreamCache.Remove(oldestKey);
            }
        }
    }

    private static void RememberTitle(string videoId, string title)
    {
        lock (TitleCacheLock)
        {
            PruneExpiredTitleCacheEntriesLocked();
            TitleCache[videoId] = new TitleCacheEntry(title, DateTimeOffset.UtcNow.Add(TitleCacheTtl));

            if (TitleCache.Count <= MaxTitleCacheEntries)
            {
                return;
            }

            string? oldestKey = null;
            var oldestExpiry = DateTimeOffset.MaxValue;
            foreach (var pair in TitleCache)
            {
                if (pair.Value.ExpiresUtc >= oldestExpiry)
                {
                    continue;
                }

                oldestKey = pair.Key;
                oldestExpiry = pair.Value.ExpiresUtc;
            }

            if (!string.IsNullOrWhiteSpace(oldestKey))
            {
                TitleCache.Remove(oldestKey);
            }
        }
    }

    private static void PruneExpiredStreamCacheEntriesLocked()
    {
        if (StreamCache.Count == 0)
        {
            return;
        }

        var now = DateTimeOffset.UtcNow;
        List<string>? expiredKeys = null;
        foreach (var pair in StreamCache)
        {
            if (pair.Value.ExpiresUtc > now)
            {
                continue;
            }

            expiredKeys ??= [];
            expiredKeys.Add(pair.Key);
        }

        if (expiredKeys is null)
        {
            return;
        }

        foreach (var key in expiredKeys)
        {
            StreamCache.Remove(key);
        }
    }

    private static void PruneExpiredTitleCacheEntriesLocked()
    {
        if (TitleCache.Count == 0)
        {
            return;
        }

        var now = DateTimeOffset.UtcNow;
        List<string>? expiredKeys = null;
        foreach (var pair in TitleCache)
        {
            if (pair.Value.ExpiresUtc > now)
            {
                continue;
            }

            expiredKeys ??= [];
            expiredKeys.Add(pair.Key);
        }

        if (expiredKeys is null)
        {
            return;
        }

        foreach (var key in expiredKeys)
        {
            TitleCache.Remove(key);
        }
    }

    private static unsafe string PtrToAnsi(byte* value)
    {
        return value == null ? string.Empty : Marshal.PtrToStringAnsi((nint)value) ?? string.Empty;
    }

    private static string Sanitize(string value)
    {
        return value.Replace('\r', ' ').Replace('\n', ' ').Replace('|', '/').Trim();
    }

    private static string SanitizePlaylistField(string value)
    {
        return Sanitize(value)
            .Replace(PlaylistMetaSeparator, ' ')
            .Replace(PlaylistRecordSeparator, ' ')
            .Replace(PlaylistFieldSeparator, ' ');
    }

    private static unsafe void WriteUtf8Output(byte* output, int outputSize, string value)
    {
        WriteBytesOutput(output, outputSize, Encoding.UTF8.GetBytes(value));
    }

    private static string DecodeXorString(byte key, params byte[] bytes)
    {
        var chars = new char[bytes.Length];
        for (var index = 0; index < bytes.Length; index++)
        {
            chars[index] = (char)(bytes[index] ^ key);
        }

        return new string(chars);
    }

    private static unsafe void WriteBytesOutput(byte* output, int outputSize, byte[] bytes)
    {
        if (output == null || outputSize <= 0)
        {
            return;
        }

        var length = Math.Min(bytes.Length, outputSize - 1);
        for (var index = 0; index < length; index++)
        {
            output[index] = bytes[index];
        }

        output[length] = 0;
    }

    private sealed record YoutubeClientProfile(string ClientName, string HeaderName, string Version, string UserAgent);
    private sealed record PlaylistPageContext(string InitialDataJson, string? ApiKey, string? VisitorData, string? ClientVersion);
    private sealed record WatchPageContext(string ApiKey, string? VisitorData);
    private sealed record StreamCacheEntry(string StreamUrl, DateTimeOffset ExpiresUtc);
    private sealed record TitleCacheEntry(string Title, DateTimeOffset ExpiresUtc);
    private sealed record PlaylistItem(string Url, string Title);
    private sealed record PlaylistResult(string Title, List<PlaylistItem> Items);
}
