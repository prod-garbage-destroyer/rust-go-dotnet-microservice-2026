use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::Json,
    routing::{get, post},
    Router,
};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use sqlx::{postgres::PgPoolOptions, PgPool};
use std::net::SocketAddr;
use tokio::task;
use uuid::Uuid;
use validator::Validate;

#[derive(Clone)]
struct AppState {
    pool: PgPool,
    notify_log_enabled: bool,
}

#[derive(Debug, Serialize, sqlx::FromRow)]
struct User {
    id: Uuid,
    name: String,
    email: String,
    created_at: DateTime<Utc>,
}

#[derive(Debug, Deserialize, Validate)]
struct CreateUserRequest {
    #[validate(length(min = 1, max = 100))]
    name: String,
    #[validate(email)]
    email: String,
}

#[derive(Serialize)]
struct HealthResponse {
    status: &'static str,
}

#[derive(Serialize)]
struct ErrorResponse {
    error: String,
}

#[derive(Debug, Deserialize, Serialize)]
struct JsonRoundtripItem {
    id: String,
    score: i64,
    enabled: bool,
    tags: Vec<String>,
}

#[derive(Debug, Deserialize, Serialize)]
struct JsonRoundtripPayload {
    tenant: String,
    region: String,
    timestamp: String,
    items: Vec<JsonRoundtripItem>,
}

#[derive(Serialize)]
struct JsonRoundtripResponse {
    tenant: String,
    region: String,
    items_count: usize,
    enabled_count: usize,
    score_sum: i64,
    tag_count: usize,
}

#[derive(Debug, Deserialize)]
struct CryptoHashPayload {
    input: String,
    rounds: Option<u32>,
}

#[derive(Serialize)]
struct CryptoHashResponse {
    algorithm: &'static str,
    rounds: u32,
    digest_hex: String,
}

async fn health() -> Json<HealthResponse> {
    Json(HealthResponse { status: "ok" })
}

async fn json_roundtrip(
    Json(payload): Json<JsonRoundtripPayload>,
) -> Result<Json<JsonRoundtripResponse>, (StatusCode, Json<ErrorResponse>)> {
    if payload.items.is_empty() {
        return Err((
            StatusCode::UNPROCESSABLE_ENTITY,
            Json(ErrorResponse {
                error: "items must contain at least 1 entry".to_string(),
            }),
        ));
    }

    let mut enabled_count = 0;
    let mut score_sum: i64 = 0;
    let mut tag_count = 0;
    for item in &payload.items {
        if item.enabled {
            enabled_count += 1;
        }
        score_sum += item.score;
        tag_count += item.tags.len();
    }

    Ok(Json(JsonRoundtripResponse {
        tenant: payload.tenant,
        region: payload.region,
        items_count: payload.items.len(),
        enabled_count,
        score_sum,
        tag_count,
    }))
}

async fn crypto_hash(
    Json(payload): Json<CryptoHashPayload>,
) -> Result<Json<CryptoHashResponse>, (StatusCode, Json<ErrorResponse>)> {
    if payload.input.is_empty() {
        return Err((
            StatusCode::UNPROCESSABLE_ENTITY,
            Json(ErrorResponse {
                error: "input must not be empty".to_string(),
            }),
        ));
    }

    let rounds = payload.rounds.unwrap_or(2000).clamp(1, 20000);
    let mut bytes = payload.input.into_bytes();

    for _ in 0..rounds {
        let mut hasher = Sha256::new();
        hasher.update(&bytes);
        let hash = hasher.finalize();
        bytes.clear();
        bytes.extend_from_slice(&hash);
    }

    let digest_hex = bytes.iter().map(|b| format!("{:02x}", b)).collect::<String>();

    Ok(Json(CryptoHashResponse {
        algorithm: "sha256",
        rounds,
        digest_hex,
    }))
}

async fn create_user(
    State(state): State<AppState>,
    Json(payload): Json<CreateUserRequest>,
) -> Result<(StatusCode, Json<User>), (StatusCode, Json<ErrorResponse>)> {
    if let Err(e) = payload.validate() {
        return Err((
            StatusCode::UNPROCESSABLE_ENTITY,
            Json(ErrorResponse {
                error: e.to_string(),
            }),
        ));
    }

    let user = sqlx::query_as::<_, User>(
        "INSERT INTO users (name, email) VALUES ($1, $2) RETURNING id, name, email, created_at",
    )
    .bind(&payload.name)
    .bind(&payload.email)
    .fetch_one(&state.pool)
    .await
    .map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ErrorResponse {
                error: e.to_string(),
            }),
        )
    })?;

    let email = user.email.clone();
    let notify_log_enabled = state.notify_log_enabled;
    if notify_log_enabled {
        task::spawn(async move {
            let ts = Utc::now();
            println!("NOTIFY: email sent to {} at {}", email, ts);
        });
    }

    Ok((StatusCode::CREATED, Json(user)))
}

async fn get_user(
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> Result<Json<User>, (StatusCode, Json<ErrorResponse>)> {
    let user =
        sqlx::query_as::<_, User>("SELECT id, name, email, created_at FROM users WHERE id = $1")
            .bind(id)
            .fetch_optional(&state.pool)
            .await
            .map_err(|e| {
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(ErrorResponse {
                        error: e.to_string(),
                    }),
                )
            })?;

    match user {
        Some(u) => Ok(Json(u)),
        None => Err((
            StatusCode::NOT_FOUND,
            Json(ErrorResponse {
                error: "user not found".to_string(),
            }),
        )),
    }
}

async fn list_users(
    State(state): State<AppState>,
) -> Result<Json<Vec<User>>, (StatusCode, Json<ErrorResponse>)> {
    let users = sqlx::query_as::<_, User>(
        "SELECT id, name, email, created_at FROM users ORDER BY created_at DESC LIMIT 100",
    )
    .fetch_all(&state.pool)
    .await
    .map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ErrorResponse {
                error: e.to_string(),
            }),
        )
    })?;

    Ok(Json(users))
}

async fn delete_user(
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> Result<StatusCode, (StatusCode, Json<ErrorResponse>)> {
    let result = sqlx::query("DELETE FROM users WHERE id = $1")
        .bind(id)
        .execute(&state.pool)
        .await
        .map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    error: e.to_string(),
                }),
            )
        })?;

    if result.rows_affected() == 0 {
        return Err((
            StatusCode::NOT_FOUND,
            Json(ErrorResponse {
                error: "user not found".to_string(),
            }),
        ));
    }

    Ok(StatusCode::NO_CONTENT)
}

#[tokio::main]
async fn main() {
    dotenvy::dotenv().ok();

    const POOL_MIN_CONNECTIONS: u32 = 5;
    const POOL_MAX_CONNECTIONS: u32 = 20;

    let database_url = std::env::var("DATABASE_URL")
        .unwrap_or_else(|_| "postgres://bench:bench@localhost:5432/bench".to_string());

    let port: u16 = std::env::var("PORT")
        .unwrap_or_else(|_| "3001".to_string())
        .parse()
        .expect("PORT must be a number");

    let notify_log_enabled = std::env::var("BENCH_NOTIFY_LOG")
        .map(|v| {
            let normalized = v.trim().to_ascii_lowercase();
            !(normalized == "0" || normalized == "false" || normalized == "off")
        })
        .unwrap_or(true);

    let pool = PgPoolOptions::new()
        .min_connections(POOL_MIN_CONNECTIONS)
        .max_connections(POOL_MAX_CONNECTIONS)
        .connect(&database_url)
        .await
        .expect("Failed to connect to database");

    sqlx::query(
        "CREATE TABLE IF NOT EXISTS users (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            name VARCHAR(100) NOT NULL,
            email VARCHAR(255) NOT NULL UNIQUE,
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )",
    )
    .execute(&pool)
    .await
    .expect("Failed to run migrations");

    let state = AppState {
        pool,
        notify_log_enabled,
    };

    let app = Router::new()
        .route("/health", get(health))
        .route("/json/roundtrip", post(json_roundtrip))
        .route("/crypto/hash", post(crypto_hash))
        .route("/users", post(create_user).get(list_users))
        .route("/users/{id}", get(get_user).delete(delete_user))
        .with_state(state);

    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    println!("rust-axum listening on {}", addr);
    println!(
        "benchmark config: pool_min={}, pool_max={}, notify_log_enabled={}",
        POOL_MIN_CONNECTIONS, POOL_MAX_CONNECTIONS, notify_log_enabled
    );

    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}
