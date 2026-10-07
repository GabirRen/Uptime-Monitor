// Package config loads worker configuration from environment variables.
package config

import (
	"strconv"
	"time"
)

// Config holds the worker's runtime configuration.
type Config struct {
	MaxConcurrency int
	ReloadInterval time.Duration
	RetentionDays  int
}

// Load builds a Config from environment variables, applying the defaults
// documented in the repository's .env.example. lookup is typically
// os.LookupEnv; it is injected so configuration parsing can be tested
// without touching the process environment.
func Load(lookup func(string) (string, bool)) Config {
	return Config{
		MaxConcurrency: intOrDefault(lookup, "WORKER_MAX_CONCURRENCY", 50),
		ReloadInterval: time.Duration(intOrDefault(lookup, "WORKER_RELOAD_SECONDS", 15)) * time.Second,
		RetentionDays:  intOrDefault(lookup, "CHECK_RETENTION_DAYS", 30),
	}
}

func intOrDefault(lookup func(string) (string, bool), key string, fallback int) int {
	value, ok := lookup(key)
	if !ok || value == "" {
		return fallback
	}

	parsed, err := strconv.Atoi(value)
	if err != nil {
		return fallback
	}

	return parsed
}
