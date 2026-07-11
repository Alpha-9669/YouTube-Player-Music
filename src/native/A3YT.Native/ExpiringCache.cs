namespace A3YT.Native;

/// <summary>
/// Small, thread-safe, bounded cache used by the unmanaged resolver exports.
/// Expiration and eviction are intentionally deterministic to keep NativeAOT
/// behavior independent from runtime memory-pressure heuristics.
/// </summary>
internal sealed class ExpiringCache<TValue>(int capacity, TimeSpan timeToLive)
    where TValue : class
{
    private readonly object _lock = new();
    private readonly Dictionary<string, Entry> _entries = new(StringComparer.Ordinal);

    public bool TryGet(string key, out TValue? value)
    {
        lock (_lock)
        {
            PruneExpired(DateTimeOffset.UtcNow);
            if (_entries.TryGetValue(key, out var entry))
            {
                value = entry.Value;
                return true;
            }

            value = null;
            return false;
        }
    }

    public void Set(string key, TValue value)
    {
        lock (_lock)
        {
            var now = DateTimeOffset.UtcNow;
            PruneExpired(now);
            _entries[key] = new Entry(value, now.Add(timeToLive));

            if (_entries.Count <= capacity)
            {
                return;
            }

            var oldest = _entries.MinBy(static pair => pair.Value.ExpiresUtc);
            _entries.Remove(oldest.Key);
        }
    }

    private void PruneExpired(DateTimeOffset now)
    {
        foreach (var key in _entries
                     .Where(pair => pair.Value.ExpiresUtc <= now)
                     .Select(static pair => pair.Key)
                     .ToArray())
        {
            _entries.Remove(key);
        }
    }

    private sealed record Entry(TValue Value, DateTimeOffset ExpiresUtc);
}
