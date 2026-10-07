package config

import (
	"testing"
	"time"
)

func TestLoadDefaults(t *testing.T) {
	lookup := func(string) (string, bool) { return "", false }

	cfg := Load(lookup)

	if cfg.MaxConcurrency != 50 {
		t.Errorf("MaxConcurrency = %d, want 50", cfg.MaxConcurrency)
	}
	if cfg.ReloadInterval != 15*time.Second {
		t.Errorf("ReloadInterval = %s, want 15s", cfg.ReloadInterval)
	}
	if cfg.RetentionDays != 30 {
		t.Errorf("RetentionDays = %d, want 30", cfg.RetentionDays)
	}
}

func TestLoadOverridesAndInvalidValues(t *testing.T) {
	values := map[string]string{
		"WORKER_MAX_CONCURRENCY": "100",
		"WORKER_RELOAD_SECONDS":  "not-a-number",
		"CHECK_RETENTION_DAYS":   "7",
	}
	lookup := func(key string) (string, bool) {
		v, ok := values[key]
		return v, ok
	}

	cfg := Load(lookup)

	if cfg.MaxConcurrency != 100 {
		t.Errorf("MaxConcurrency = %d, want 100", cfg.MaxConcurrency)
	}
	if cfg.ReloadInterval != 15*time.Second {
		t.Errorf("ReloadInterval = %s, want fallback 15s for invalid input", cfg.ReloadInterval)
	}
	if cfg.RetentionDays != 7 {
		t.Errorf("RetentionDays = %d, want 7", cfg.RetentionDays)
	}
}
