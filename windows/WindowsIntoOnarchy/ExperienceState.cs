using System;
using System.Text.Json.Serialization;

namespace WindowsIntoOnarchy;

public sealed record ExperienceState
{
    [JsonPropertyName("schemaVersion")] public int SchemaVersion { get; init; } = 1;
    [JsonPropertyName("phase")] public string Phase { get; init; } = "Checking";
    [JsonPropertyName("headline")] public string Headline { get; init; } = "Checking this PC";
    [JsonPropertyName("detail")] public string Detail { get; init; } = "This only takes a moment.";
    [JsonPropertyName("percent")] public int Percent { get; init; }
    [JsonPropertyName("indeterminate")] public bool Indeterminate { get; init; }
    [JsonPropertyName("action")] public string Action { get; init; } = "";
    [JsonPropertyName("errorCode")] public string ErrorCode { get; init; } = "";
    [JsonPropertyName("updatedAtUtc")] public DateTime UpdatedAtUtc { get; init; }
}
