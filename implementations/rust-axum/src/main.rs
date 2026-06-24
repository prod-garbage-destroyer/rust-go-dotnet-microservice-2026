use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::Json,
    routing::{get, post},
    Router,
};
use chrono::{DateTime, Utc};
use microservice_codegen::deadpool_postgres::{Config, ManagerConfig, Pool, RecyclingMethod, Runtime};
use microservice_codegen::queries::users;
use microservice_codegen::tokio_postgres;
use serde::{Deserialize, Serialize};
use std::net::SocketAddr;
use tokio::task;
use uuid::Uuid;
use validator::Validate;

#[derive(Clone)]
struct AppState {
    pool: Pool,
}

#[derive(Debug, Serialize)]
struct User {
    id: Uuid,
    name: String,
    email: String,
    created_at: DateTime<Utc>,
}

impl From<users::GetUser> for User {
    fn from(u: users::GetUser) -> Self {
        User {
            id: u.id,
            name: u.name,
            email: u.email,
            created_at: u.created_at.with_timezone(&Utc),
        }
    }
}

impl From<users::ListUsers> for User {
    fn from(u: users::ListUsers) -> Self {
        User {
            id: u.id,
            name: u.name,
            email: u.email,
            created_at: u.created_at.with_timezone(&Utc),
        }
    }
}

impl From<users::InsertUser> for User {
    fn from(u: users::InsertUser) -> Self {
        User {
            id: u.id,
            name: u.name,
            email: u.email,
            created_at: u.created_at.with_timezone(&Utc),
        }
    }
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

fn internal_error(e: tokio_postgres::Error) -> (StatusCode, Json<ErrorResponse>) {
    (
        StatusCode::INTERNAL_SERVER_ERROR,
        Json(ErrorResponse { error: e.to_string() }),
    )
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

    let client = state.pool.get().await.map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ErrorResponse { error: e.to_string() }),
        )
    })?;

    let inserted = users::insert_user()
        .bind(&client, &payload.name, &payload.email)
        .one()
        .await
        .map_err(internal_error)?;

    let user: User = inserted.into();
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
    let client = state.pool.get().await.map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ErrorResponse { error: e.to_string() }),
        )
    })?;

    let row = users::get_user()
        .bind(&client, &id)
        .opt()
        .await
        .map_err(internal_error)?;

    match row {
        Some(u) => Ok(Json(u.into())),
        None => Err((
            StatusCode::NOT_FOUND,
            Json(ErrorResponse { error: "user not found".to_string() }),
        )),
    }
}

async fn list_users(
    State(state): State<AppState>,
) -> Result<Json<Vec<User>>, (StatusCode, Json<ErrorResponse>)> {
    let client = state.pool.get().await.map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ErrorResponse { error: e.to_string() }),
        )
    })?;

    let rows = users::list_users()
        .bind(&client)
        .all()
        .await
        .map_err(internal_error)?;

    Ok(Json(rows.into_iter().map(User::from).collect()))
}

async fn delete_user(
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> Result<StatusCode, (StatusCode, Json<ErrorResponse>)> {
    let client = state.pool.get().await.map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ErrorResponse { error: e.to_string() }),
        )
    })?;

    let deleted = users::delete_user()
        .bind(&client, &id)
        .opt()
        .await
        .map_err(internal_error)?;

    match deleted {
        Some(_) => Ok(StatusCode::NO_CONTENT),
        None => Err((
            StatusCode::NOT_FOUND,
            Json(ErrorResponse { error: "user not found".to_string() }),
        )),
    }
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

    let pg_config = database_url
        .parse::<tokio_postgres::Config>()
        .expect("invalid DATABASE_URL");

    let mut cfg = Config::new();
    cfg.host = pg_config.get_hosts().first().and_then(|h| match h {
        tokio_postgres::config::Host::Tcp(s) => Some(s.clone()),
        #[allow(unreachable_patterns)]
        _ => None,
    });
    cfg.port = pg_config.get_ports().first().copied();
    cfg.user = pg_config.get_user().map(|s| s.to_string());
    cfg.password = pg_config
        .get_password()
        .map(|p| String::from_utf8_lossy(p).to_string());
    cfg.dbname = pg_config.get_dbname().map(|s| s.to_string());
    cfg.manager = Some(ManagerConfig {
        recycling_method: RecyclingMethod::Fast,
    });

    let pool = cfg
        .create_pool(Some(Runtime::Tokio1), tokio_postgres::NoTls)
        .expect("Failed to create pool");

    pool.resize(20);

    // deadpool has no native "min_connections"; pre-warm 5 idle connections
    // up front to match the min=5/max=20 pool sizing used by the other targets.
    {
        let mut warm = Vec::with_capacity(5);
        for _ in 0..5 {
            warm.push(pool.get().await.expect("Failed to pre-warm connection pool"));
        }
    }

    {
        let client = pool.get().await.expect("Failed to connect to database");
        client
            .execute(
                "CREATE TABLE IF NOT EXISTS users (
                    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                    name VARCHAR(100) NOT NULL,
                    email VARCHAR(255) NOT NULL UNIQUE,
                    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
                )",
                &[],
            )
            .await
            .expect("Failed to run migrations");
    }

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
