using System.ComponentModel.DataAnnotations;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Serialization;
using Npgsql;

var builder = WebApplication.CreateBuilder(args);

const int PoolMinSize = 5;
const int PoolMaxSize = 20;

var databaseUrl = Environment.GetEnvironmentVariable("DATABASE_URL")
    ?? "Host=localhost;Port=5432;Database=bench;Username=bench;Password=bench";
var port = int.Parse(Environment.GetEnvironmentVariable("PORT") ?? "3003");

var notifyLogEnabled = true;
var notifyLogRaw = Environment.GetEnvironmentVariable("BENCH_NOTIFY_LOG");
if (!string.IsNullOrWhiteSpace(notifyLogRaw))
{
    var normalized = notifyLogRaw.Trim().ToLowerInvariant();
    if (normalized is "0" or "false" or "off")
    {
        notifyLogEnabled = false;
    }
}

var connBuilder = new NpgsqlConnectionStringBuilder(databaseUrl)
{
    MinPoolSize = PoolMinSize,
    MaxPoolSize = PoolMaxSize
};
databaseUrl = connBuilder.ConnectionString;

var dataSourceBuilder = new NpgsqlDataSourceBuilder(databaseUrl);
var dataSource = dataSourceBuilder.Build();

builder.Services.AddSingleton(dataSource);
builder.Services.ConfigureHttpJsonOptions(options =>
{
    options.SerializerOptions.TypeInfoResolverChain.Insert(0, AppJsonSerializerContext.Default);
});
builder.WebHost.UseUrls($"http://0.0.0.0:{port}");

var app = builder.Build();

// Run migrations
await using var migConn = await dataSource.OpenConnectionAsync();
await using var migCmd = new NpgsqlCommand(@"
    CREATE TABLE IF NOT EXISTS users (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        name VARCHAR(100) NOT NULL,
        email VARCHAR(255) NOT NULL UNIQUE,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )", migConn);
await migCmd.ExecuteNonQueryAsync();

Console.WriteLine($"dotnet-minimal listening on port {port}");
Console.WriteLine(
    $"benchmark config: pool_min={PoolMinSize}, pool_max={PoolMaxSize}, notify_log_enabled={notifyLogEnabled}");

app.MapGet("/health", () => Results.Ok(new HealthResponse("ok")));

app.MapPost("/json/roundtrip", (JsonRoundtripPayload payload) =>
{
    if (payload.Items is null || payload.Items.Count == 0)
    {
        return Results.UnprocessableEntity(new ErrorResponse("items must contain at least 1 entry"));
    }

    var enabledCount = payload.Items.Count(item => item.Enabled);
    var scoreSum = payload.Items.Sum(item => item.Score);
    var tagCount = payload.Items.Sum(item => item.Tags?.Count ?? 0);

    return Results.Ok(new JsonRoundtripResponse(
        payload.Tenant,
        payload.Region,
        payload.Items.Count,
        enabledCount,
        scoreSum,
        tagCount
    ));
});

app.MapPost("/crypto/hash", (CryptoHashPayload payload) =>
{
    if (string.IsNullOrWhiteSpace(payload.Input))
    {
        return Results.UnprocessableEntity(new ErrorResponse("input must not be empty"));
    }

    var rounds = payload.Rounds ?? 2000;
    rounds = Math.Clamp(rounds, 1, 20000);

    var bytes = Encoding.UTF8.GetBytes(payload.Input);
    for (var i = 0; i < rounds; i++)
    {
        bytes = SHA256.HashData(bytes);
    }

    var digestHex = Convert.ToHexString(bytes).ToLowerInvariant();
    return Results.Ok(new CryptoHashResponse("sha256", rounds, digestHex));
});

app.MapPost("/users", async (CreateUserRequest req, NpgsqlDataSource ds) =>
{
    var errors = new List<ValidationResult>();
    var ctx = new ValidationContext(req);
    if (!Validator.TryValidateObject(req, ctx, errors, true))
    {
        return Results.UnprocessableEntity(new ErrorResponse(string.Join("; ", errors.Select(e => e.ErrorMessage))));
    }

    await using var conn = await ds.OpenConnectionAsync();
    await using var cmd = new NpgsqlCommand(
        "INSERT INTO users (name, email) VALUES (@name, @email) RETURNING id, name, email, created_at",
        conn);
    cmd.Parameters.AddWithValue("name", req.Name);
    cmd.Parameters.AddWithValue("email", req.Email);

    await using var reader = await cmd.ExecuteReaderAsync();
    if (!await reader.ReadAsync())
        return Results.Problem("Insert failed");

    var user = new UserDto(
        reader.GetGuid(0),
        reader.GetString(1),
        reader.GetString(2),
        reader.GetDateTime(3)
    );

    // Non-blocking background job
    _ = Task.Run(() =>
    {
        if (notifyLogEnabled)
        {
            Console.WriteLine($"NOTIFY: email sent to {user.Email} at {DateTime.UtcNow:O}");
        }
    });

    return Results.Created($"/users/{user.Id}", user);
});

app.MapGet("/users/{id:guid}", async (Guid id, NpgsqlDataSource ds) =>
{
    await using var conn = await ds.OpenConnectionAsync();
    await using var cmd = new NpgsqlCommand(
        "SELECT id, name, email, created_at FROM users WHERE id = @id", conn);
    cmd.Parameters.AddWithValue("id", id);

    await using var reader = await cmd.ExecuteReaderAsync();
    if (!await reader.ReadAsync())
        return Results.NotFound(new ErrorResponse("user not found"));

    return Results.Ok(new UserDto(
        reader.GetGuid(0),
        reader.GetString(1),
        reader.GetString(2),
        reader.GetDateTime(3)
    ));
});

app.MapGet("/users", async (NpgsqlDataSource ds) =>
{
    await using var conn = await ds.OpenConnectionAsync();
    await using var cmd = new NpgsqlCommand(
        "SELECT id, name, email, created_at FROM users ORDER BY created_at DESC LIMIT 100", conn);

    await using var reader = await cmd.ExecuteReaderAsync();
    var users = new List<UserDto>();
    while (await reader.ReadAsync())
    {
        users.Add(new UserDto(
            reader.GetGuid(0),
            reader.GetString(1),
            reader.GetString(2),
            reader.GetDateTime(3)
        ));
    }
    return Results.Ok(users);
});

app.MapDelete("/users/{id:guid}", async (Guid id, NpgsqlDataSource ds) =>
{
    await using var conn = await ds.OpenConnectionAsync();
    await using var cmd = new NpgsqlCommand("DELETE FROM users WHERE id = @id", conn);
    cmd.Parameters.AddWithValue("id", id);

    var rows = await cmd.ExecuteNonQueryAsync();
    return rows == 0
        ? Results.NotFound(new ErrorResponse("user not found"))
        : Results.NoContent();
});

await app.RunAsync();

record CreateUserRequest(
    [property: Required, StringLength(100, MinimumLength = 1)] string Name,
    [property: Required, EmailAddress] string Email
);

record UserDto(
    [property: JsonPropertyName("id")] Guid Id,
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("email")] string Email,
    [property: JsonPropertyName("created_at")] DateTime CreatedAt
);

record JsonRoundtripItem(
    [property: JsonPropertyName("id")] string Id,
    [property: JsonPropertyName("score")] long Score,
    [property: JsonPropertyName("enabled")] bool Enabled,
    [property: JsonPropertyName("tags")] List<string> Tags
);

record JsonRoundtripPayload(
    [property: JsonPropertyName("tenant")] string Tenant,
    [property: JsonPropertyName("region")] string Region,
    [property: JsonPropertyName("timestamp")] string Timestamp,
    [property: JsonPropertyName("items")] List<JsonRoundtripItem> Items
);

record JsonRoundtripResponse(
    [property: JsonPropertyName("tenant")] string Tenant,
    [property: JsonPropertyName("region")] string Region,
    [property: JsonPropertyName("items_count")] int ItemsCount,
    [property: JsonPropertyName("enabled_count")] int EnabledCount,
    [property: JsonPropertyName("score_sum")] long ScoreSum,
    [property: JsonPropertyName("tag_count")] int TagCount
);

record CryptoHashPayload(
    [property: JsonPropertyName("input")] string Input,
    [property: JsonPropertyName("rounds")] int? Rounds
);

record CryptoHashResponse(
    [property: JsonPropertyName("algorithm")] string Algorithm,
    [property: JsonPropertyName("rounds")] int Rounds,
    [property: JsonPropertyName("digest_hex")] string DigestHex
);

record HealthResponse(
    [property: JsonPropertyName("status")] string Status
);

record ErrorResponse(
    [property: JsonPropertyName("error")] string Error
);

[JsonSourceGenerationOptions(PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
[JsonSerializable(typeof(CreateUserRequest))]
[JsonSerializable(typeof(UserDto))]
[JsonSerializable(typeof(List<UserDto>))]
[JsonSerializable(typeof(JsonRoundtripItem))]
[JsonSerializable(typeof(JsonRoundtripPayload))]
[JsonSerializable(typeof(JsonRoundtripResponse))]
[JsonSerializable(typeof(CryptoHashPayload))]
[JsonSerializable(typeof(CryptoHashResponse))]
[JsonSerializable(typeof(HealthResponse))]
[JsonSerializable(typeof(ErrorResponse))]
internal partial class AppJsonSerializerContext : JsonSerializerContext
{
}
