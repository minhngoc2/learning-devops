package httpx

import (
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
)

const maxBodyBytes = 1 << 20

// WriteJSON writes v as JSON with the given status.
func WriteJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

// WriteError writes {"error":msg}.
func WriteError(w http.ResponseWriter, status int, msg string) {
	WriteJSON(w, status, map[string]string{"error": msg})
}

// Internal logs err at error level under msg and answers 500 {"error":"internal error"}, so callers never
// see internal details.
func Internal(w http.ResponseWriter, log *slog.Logger, msg string, err error) {
	log.Error(msg, "err", err)
	WriteError(w, http.StatusInternalServerError, "internal error")
}

// DecodeJSON decodes one JSON value from a body of at most 1 MiB; trailing data is an error.
func DecodeJSON(r *http.Request, v any) error {
	dec := json.NewDecoder(http.MaxBytesReader(nil, r.Body, maxBodyBytes))
	if err := dec.Decode(v); err != nil {
		return err
	}
	if err := dec.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return errors.New("body must contain a single JSON value")
	}
	return nil
}
