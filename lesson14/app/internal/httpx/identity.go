package httpx

import "net/http"

// Identity is the caller as verified upstream: API Gateway's JWT authorizer (or AUTH_MODE=local) sets
// the X-Customer-* headers, and the ALB only accepts requests carrying the origin secret.
type Identity struct{ Sub, Email string }

// IdentityFrom reads X-Customer-Sub and X-Customer-Email. ok is false without a sub; Email may be empty.
func IdentityFrom(r *http.Request) (Identity, bool) {
	id := Identity{Sub: r.Header.Get("X-Customer-Sub"), Email: r.Header.Get("X-Customer-Email")}
	return id, id.Sub != ""
}

// RequireIdentity answers 401 {"error":"unauthenticated"} when the request carries no customer sub.
func RequireIdentity(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if _, ok := IdentityFrom(r); !ok {
			WriteError(w, http.StatusUnauthorized, "unauthenticated")
			return
		}
		next.ServeHTTP(w, r)
	})
}
