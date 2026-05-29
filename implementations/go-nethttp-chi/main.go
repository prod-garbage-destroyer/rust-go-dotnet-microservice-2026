package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-playground/validator/v10"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type User struct {
	ID        uuid.UUID `json:"id"`
	Name      string    `json:"name"`
	Email     string    `json:"email"`
	CreatedAt time.Time `json:"created_at"`
}

type CreateUserRequest struct {
	Name  string `json:"name" validate:"required,min=1,max=100"`
	Email string `json:"email" validate:"required,email"`
}

type HealthResponse struct {
	Status string `json:"status"`
}

type ErrorResponse struct {
	Error string `json:"error"`
}

type JsonRoundtripItem struct {
	ID      string   `json:"id"`
	Score   int64    `json:"score"`
	Enabled bool     `json:"enabled"`
	Tags    []string `json:"tags"`
}

type JsonRoundtripPayload struct {
	Tenant    string              `json:"tenant"`
	Region    string              `json:"region"`
	Timestamp string              `json:"timestamp"`
	Items     []JsonRoundtripItem `json:"items"`
}

type JsonRoundtripResponse struct {
	Tenant       string `json:"tenant"`
	Region       string `json:"region"`
	ItemsCount   int    `json:"items_count"`
	EnabledCount int    `json:"enabled_count"`
	ScoreSum     int64  `json:"score_sum"`
	TagCount     int    `json:"tag_count"`
}

type CryptoHashPayload struct {
	Input  string `json:"input"`
	Rounds *int   `json:"rounds"`
}

type CryptoHashResponse struct {
	Algorithm string `json:"algorithm"`
	Rounds    int    `json:"rounds"`
	DigestHex string `json:"digest_hex"`
}

var validate = validator.New()

const (
	poolMinConns int32 = 5
	poolMaxConns int32 = 20
)

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func main() {
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		dbURL = "postgres://bench:bench@localhost:5432/bench"
	}
	port := os.Getenv("PORT")
	if port == "" {
		port = "3005"
	}

	config, err := pgxpool.ParseConfig(dbURL)
	if err != nil {
		log.Fatal("Failed to parse DB config:", err)
	}
	config.MinConns = poolMinConns
	config.MaxConns = poolMaxConns

	pool, err := pgxpool.NewWithConfig(context.Background(), config)
	if err != nil {
		log.Fatal("Failed to connect to database:", err)
	}
	defer pool.Close()

	notifyLogEnabled := true
	if v, ok := os.LookupEnv("BENCH_NOTIFY_LOG"); ok {
		switch v {
		case "0", "false", "FALSE", "off", "OFF":
			notifyLogEnabled = false
		}
	}

	// Run migrations
	_, err = pool.Exec(context.Background(), `
		CREATE TABLE IF NOT EXISTS users (
			id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
			name VARCHAR(100) NOT NULL,
			email VARCHAR(255) NOT NULL UNIQUE,
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		)
	`)
	if err != nil {
		log.Fatal("Failed to run migrations:", err)
	}

	r := chi.NewRouter()

	r.Get("/health", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, HealthResponse{Status: "ok"})
	})

	r.Post("/json/roundtrip", func(w http.ResponseWriter, r *http.Request) {
		var payload JsonRoundtripPayload
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			writeJSON(w, http.StatusUnprocessableEntity, ErrorResponse{Error: err.Error()})
			return
		}
		if len(payload.Items) == 0 {
			writeJSON(w, http.StatusUnprocessableEntity, ErrorResponse{Error: "items must contain at least 1 entry"})
			return
		}

		enabledCount := 0
		scoreSum := int64(0)
		tagCount := 0
		for _, item := range payload.Items {
			if item.Enabled {
				enabledCount++
			}
			scoreSum += item.Score
			tagCount += len(item.Tags)
		}

		writeJSON(w, http.StatusOK, JsonRoundtripResponse{
			Tenant:       payload.Tenant,
			Region:       payload.Region,
			ItemsCount:   len(payload.Items),
			EnabledCount: enabledCount,
			ScoreSum:     scoreSum,
			TagCount:     tagCount,
		})
	})

	r.Post("/crypto/hash", func(w http.ResponseWriter, r *http.Request) {
		var payload CryptoHashPayload
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			writeJSON(w, http.StatusUnprocessableEntity, ErrorResponse{Error: err.Error()})
			return
		}
		if payload.Input == "" {
			writeJSON(w, http.StatusUnprocessableEntity, ErrorResponse{Error: "input must not be empty"})
			return
		}

		rounds := 2000
		if payload.Rounds != nil {
			rounds = *payload.Rounds
		}
		if rounds < 1 {
			rounds = 1
		}
		if rounds > 20000 {
			rounds = 20000
		}

		bytes := []byte(payload.Input)
		for i := 0; i < rounds; i++ {
			hash := sha256.Sum256(bytes)
			bytes = hash[:]
		}

		writeJSON(w, http.StatusOK, CryptoHashResponse{
			Algorithm: "sha256",
			Rounds:    rounds,
			DigestHex: hex.EncodeToString(bytes),
		})
	})

	r.Post("/users", func(w http.ResponseWriter, r *http.Request) {
		var req CreateUserRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeJSON(w, http.StatusUnprocessableEntity, ErrorResponse{Error: err.Error()})
			return
		}
		if err := validate.Struct(req); err != nil {
			writeJSON(w, http.StatusUnprocessableEntity, ErrorResponse{Error: err.Error()})
			return
		}

		var user User
		err := pool.QueryRow(context.Background(),
			"INSERT INTO users (name, email) VALUES ($1, $2) RETURNING id, name, email, created_at",
			req.Name, req.Email,
		).Scan(&user.ID, &user.Name, &user.Email, &user.CreatedAt)
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, ErrorResponse{Error: err.Error()})
			return
		}

		// Non-blocking background job
		if notifyLogEnabled {
			go func(email string) {
				fmt.Printf("NOTIFY: email sent to %s at %s\n", email, time.Now().Format(time.RFC3339))
			}(user.Email)
		}

		writeJSON(w, http.StatusCreated, user)
	})

	r.Get("/users/{id}", func(w http.ResponseWriter, r *http.Request) {
		id, err := uuid.Parse(chi.URLParam(r, "id"))
		if err != nil {
			writeJSON(w, http.StatusNotFound, ErrorResponse{Error: "invalid uuid"})
			return
		}

		var user User
		err = pool.QueryRow(context.Background(),
			"SELECT id, name, email, created_at FROM users WHERE id = $1", id,
		).Scan(&user.ID, &user.Name, &user.Email, &user.CreatedAt)
		if err == pgx.ErrNoRows {
			writeJSON(w, http.StatusNotFound, ErrorResponse{Error: "user not found"})
			return
		}
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, ErrorResponse{Error: err.Error()})
			return
		}

		writeJSON(w, http.StatusOK, user)
	})

	r.Get("/users", func(w http.ResponseWriter, r *http.Request) {
		rows, err := pool.Query(context.Background(),
			"SELECT id, name, email, created_at FROM users ORDER BY created_at DESC LIMIT 100",
		)
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, ErrorResponse{Error: err.Error()})
			return
		}
		defer rows.Close()

		users := make([]User, 0)
		for rows.Next() {
			var u User
			if err := rows.Scan(&u.ID, &u.Name, &u.Email, &u.CreatedAt); err != nil {
				writeJSON(w, http.StatusInternalServerError, ErrorResponse{Error: err.Error()})
				return
			}
			users = append(users, u)
		}

		writeJSON(w, http.StatusOK, users)
	})

	r.Delete("/users/{id}", func(w http.ResponseWriter, r *http.Request) {
		id, err := uuid.Parse(chi.URLParam(r, "id"))
		if err != nil {
			writeJSON(w, http.StatusNotFound, ErrorResponse{Error: "invalid uuid"})
			return
		}

		ct, err := pool.Exec(context.Background(), "DELETE FROM users WHERE id = $1", id)
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, ErrorResponse{Error: err.Error()})
			return
		}
		if ct.RowsAffected() == 0 {
			writeJSON(w, http.StatusNotFound, ErrorResponse{Error: "user not found"})
			return
		}

		w.WriteHeader(http.StatusNoContent)
	})

	log.Printf("go-nethttp-chi listening on :%s", port)
	log.Printf(
		"benchmark config: pool_min=%d, pool_max=%d, notify_log_enabled=%t",
		poolMinConns,
		poolMaxConns,
		notifyLogEnabled,
	)
	log.Fatal(http.ListenAndServe(":"+port, r))
}
