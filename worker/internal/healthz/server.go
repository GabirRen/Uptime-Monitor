// Package healthz exposes a minimal internal HTTP endpoint used only by
// Docker's HEALTHCHECK; it is not part of the public API contract.
package healthz

import "net/http"

// NewServer returns an *http.Server serving "ok" on /healthz at addr.
func NewServer(addr string) *http.Server {
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})

	return &http.Server{
		Addr:    addr,
		Handler: mux,
	}
}
