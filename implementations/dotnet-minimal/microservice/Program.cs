using System.ComponentModel.DataAnnotations;
using System.Text.Json.Serialization;
using Npgsql;

var builder = WebApplication.CreateBuilder(args);

var databaseUrl = Environment.GetEnvironmentVariable("DATABASE_URL")
    ?? "Host=localhost;Port=5432;Database=bench;Username=bench;Password=bench";
var port = int.Parse(Environment.GetEnvironmentVariable("PORT") ?? "3003");

var dataSourceBuilder = new NpgsqlDataSourceBuilder(databaseUrl);
var dataSource = dataSourceBuilder.Build();

builder.Services.AddSingleton(dataSource);
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

app.MapGet("/health", () => Results.Ok(new { status = "ok" }));

app.MapPost("/users", async (CreateUserRequest req, NpgsqlDataSource ds) =>
{
    var errors = new List<ValidationResult>();
    var ctx = new ValidationContext(req);
    if (!Validator.TryValidateObject(req, ctx, errors, true))
    {
        return Results.UnprocessableEntity(new { error = string.Join("; ", errors.Select(e => e.ErrorMessage)) });
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
        Console.WriteLine($"NOTIFY: email sent to {user.Email} at {DateTime.UtcNow:O}"));

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
        return Results.NotFound(new { error = "user not found" });

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
        ? Results.NotFound(new { error = "user not found" })
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
