// Command worker runs the Uptime Monitor check scheduler.
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/GabirRen/Uptime-Monitor/worker/internal/config"
	"github.com/GabirRen/Uptime-Monitor/worker/internal/healthz"
)

// healthzAddr is internal-only: it backs the container's HEALTHCHECK and is
// never exposed outside the Docker network, so it is not an env var.
const healthzAddr = ":9090"

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))

	cfg := config.Load(os.LookupEnv)
	logger.Info("worker starting",
		"max_concurrency", cfg.MaxConcurrency,
		"reload_interval", cfg.ReloadInterval.String(),
		"retention_days", cfg.RetentionDays,
	)

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	server := healthz.NewServer(healthzAddr)
	go func() {
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			logger.Error("healthz server failed", "error", err)
		}
	}()

	<-ctx.Done()
	logger.Info("shutdown signal received")

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := server.Shutdown(shutdownCtx); err != nil {
		logger.Error("healthz server shutdown failed", "error", err)
	}

	logger.Info("worker stopped")
}
