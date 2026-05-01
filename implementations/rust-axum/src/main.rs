use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::Json,
    routing::{delete, get, post},
    Router,
};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{postgres::PgPoolOptions, PgPool};
use std::net::SocketAddr;
use tokio::task;
use uuid::Uuid;
use validator::Validate;

#[derive(Clone)]
struct AppState {
    pool: PgPool,
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

async fn health() -> Json<HealthResponse> {
    Json(HealthResponse { status: "ok" })
}

async fn create_user(
    State(state): State<AppState>,
    Json(payload): Json<CreateUserRequest>,
) -> Result<(StatusCode, Json<User>), (StatusCode, Json<ErrorResponse>)> {
    if let Err(e) = payload.validate() {
        return Err((
            StatusCode::UNPROCESSABLE_ENTITY,
            Json(ErrorResponse { error: e.to_string() }),
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
            Json(ErrorResponse { error: e.to_string() }),
        )
    })?;

    let email = user.email.clone();
    task::spawn(async move {
        let ts = Utc::now();
        println!("NOTIFY: email sent to {} at {}", email, ts);
    });

    Ok((StatusCode::CREATED, Json(user)))
}

async fn get_user(
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> Result<Json<User>, (StatusCode, Json<ErrorResponse>)> {
    let user = sqlx::query_as::<_, User>(
        "SELECT id, name, email, created_at FROM users WHERE id = $1",
    )
    .bind(id)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ErrorResponse { error: e.to_string() }),
        )
    })?;

    match user {
        Some(u) => Ok(Json(u)),
        None => Err((
            StatusCode::NOT_FOUND,
            Json(ErrorResponse { error: "user not found".to_string() }),
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
            Json(ErrorResponse { error: e.to_string() }),
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
                Json(ErrorResponse { error: e.to_string() }),
            )
        })?;

    if result.rows_affected() == 0 {
        return Err((
            StatusCode::NOT_FOUND,
            Json(ErrorResponse { error: "user not found".to_string() }),
        ));
    }

    Ok(StatusCode::NO_CONTENT)
}

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt::init();
    dotenvy::dotenv().ok();

    let database_url = std::env::var("DATABASE_URL")
        .unwrap_or_else(|_| "postgres://bench:bench@localhost:5432/bench".to_string());

    let port: u16 = std::env::var("PORT")
        .unwrap_or_else(|_| "3001".to_string())
        .parse()
        .expect("PORT must be a number");

    let pool = PgPoolOptions::new()
        .min_connections(5)
        .max_connections(20)
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

    let state = AppState { pool };

    let app = Router::new()
        .route("/health", get(health))
        .route("/users", post(create_user).get(list_users))
        .route("/users/{id}", get(get_user).delete(delete_user))
        .with_state(state);

    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    println!("rust-axum listening on {}", addr);

    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}
