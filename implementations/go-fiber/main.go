package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"log"
	"os"
	"time"

	"github.com/go-playground/validator/v10"
	"github.com/gofiber/fiber/v2"
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

func main() {
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		dbURL = "postgres://bench:bench@localhost:5432/bench"
	}
	port := os.Getenv("PORT")
	if port == "" {
		port = "3002"
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

	app := fiber.New(fiber.Config{
		DisableStartupMessage: false,
	})

	app.Get("/health", func(c *fiber.Ctx) error {
		return c.JSON(HealthResponse{Status: "ok"})
	})

	app.Post("/json/roundtrip", func(c *fiber.Ctx) error {
		var payload JsonRoundtripPayload
		if err := c.BodyParser(&payload); err != nil {
			return c.Status(422).JSON(ErrorResponse{Error: err.Error()})
		}
		if len(payload.Items) == 0 {
			return c.Status(422).JSON(ErrorResponse{Error: "items must contain at least 1 entry"})
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

		return c.JSON(JsonRoundtripResponse{
			Tenant:       payload.Tenant,
			Region:       payload.Region,
			ItemsCount:   len(payload.Items),
			EnabledCount: enabledCount,
			ScoreSum:     scoreSum,
			TagCount:     tagCount,
		})
	})

	app.Post("/crypto/hash", func(c *fiber.Ctx) error {
		var payload CryptoHashPayload
		if err := c.BodyParser(&payload); err != nil {
			return c.Status(422).JSON(ErrorResponse{Error: err.Error()})
		}
		if payload.Input == "" {
			return c.Status(422).JSON(ErrorResponse{Error: "input must not be empty"})
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

		return c.JSON(CryptoHashResponse{
			Algorithm: "sha256",
			Rounds:    rounds,
			DigestHex: hex.EncodeToString(bytes),
		})
	})

	app.Post("/users", func(c *fiber.Ctx) error {
		var req CreateUserRequest
		if err := c.BodyParser(&req); err != nil {
			return c.Status(422).JSON(ErrorResponse{Error: err.Error()})
		}
		if err := validate.Struct(req); err != nil {
			return c.Status(422).JSON(ErrorResponse{Error: err.Error()})
		}

		var user User
		err := pool.QueryRow(context.Background(),
			"INSERT INTO users (name, email) VALUES ($1, $2) RETURNING id, name, email, created_at",
			req.Name, req.Email,
		).Scan(&user.ID, &user.Name, &user.Email, &user.CreatedAt)
		if err != nil {
			return c.Status(500).JSON(ErrorResponse{Error: err.Error()})
		}

		// Non-blocking background job
		go func(email string) {
			if notifyLogEnabled {
				fmt.Printf("NOTIFY: email sent to %s at %s\n", email, time.Now().Format(time.RFC3339))
			}
		}(user.Email)

		return c.Status(201).JSON(user)
	})

	app.Get("/users/:id", func(c *fiber.Ctx) error {
		id, err := uuid.Parse(c.Params("id"))
		if err != nil {
			return c.Status(404).JSON(ErrorResponse{Error: "invalid uuid"})
		}

		var user User
		err = pool.QueryRow(context.Background(),
			"SELECT id, name, email, created_at FROM users WHERE id = $1", id,
		).Scan(&user.ID, &user.Name, &user.Email, &user.CreatedAt)
		if err == pgx.ErrNoRows {
			return c.Status(404).JSON(ErrorResponse{Error: "user not found"})
		}
		if err != nil {
			return c.Status(500).JSON(ErrorResponse{Error: err.Error()})
		}

		return c.JSON(user)
	})

	app.Get("/users", func(c *fiber.Ctx) error {
		rows, err := pool.Query(context.Background(),
			"SELECT id, name, email, created_at FROM users ORDER BY created_at DESC LIMIT 100",
		)
		if err != nil {
			return c.Status(500).JSON(ErrorResponse{Error: err.Error()})
		}
		defer rows.Close()

		users := make([]User, 0)
		for rows.Next() {
			var u User
			if err := rows.Scan(&u.ID, &u.Name, &u.Email, &u.CreatedAt); err != nil {
				return c.Status(500).JSON(ErrorResponse{Error: err.Error()})
			}
			users = append(users, u)
		}

		return c.JSON(users)
	})

	app.Delete("/users/:id", func(c *fiber.Ctx) error {
		id, err := uuid.Parse(c.Params("id"))
		if err != nil {
			return c.Status(404).JSON(ErrorResponse{Error: "invalid uuid"})
		}

		ct, err := pool.Exec(context.Background(), "DELETE FROM users WHERE id = $1", id)
		if err != nil {
			return c.Status(500).JSON(ErrorResponse{Error: err.Error()})
		}
		if ct.RowsAffected() == 0 {
			return c.Status(404).JSON(ErrorResponse{Error: "user not found"})
		}

		return c.SendStatus(204)
	})

	log.Printf("go-fiber listening on :%s", port)
	log.Printf(
		"benchmark config: pool_min=%d, pool_max=%d, notify_log_enabled=%t",
		poolMinConns,
		poolMaxConns,
		notifyLogEnabled,
	)
	log.Fatal(app.Listen(":" + port))
}
