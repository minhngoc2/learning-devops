// Package dbinit builds the bootstrap SQL that gives each database-owning service its own schema and
// login role on the shared PostgreSQL instance (ADR-0002). Every statement is idempotent, so db-init can
// be re-run after a password rotation or when a service is added.
package dbinit

import (
	"errors"
	"fmt"
	"strings"
)

// Service is one database-owning service: the key in the roles map and the schema it owns.
type Service struct{ Key, Schema string }

// Services in the global order; each owns schema Schema and logs in as svc_<Key>.
var Services = []Service{{"user", "users"}, {"product", "products"}, {"order", "orders"}, {"payment", "payments"}}

// Validate checks that roles has a non-empty password without NUL bytes for every service.
func Validate(roles map[string]string) error {
	var errs []error
	for _, s := range Services {
		pw, ok := roles[s.Key]
		switch {
		case !ok || pw == "":
			errs = append(errs, fmt.Errorf("no password for svc_%s", s.Key))
		case strings.ContainsRune(pw, 0):
			errs = append(errs, fmt.Errorf("password for svc_%s contains a NUL byte", s.Key))
		}
	}
	return errors.Join(errs...)
}

// Statements returns, per service in order: create the schema, create the role if missing, set its
// password, let it use and create objects in its own schema only, give it every table created there later,
// and revoke PUBLIC's default access. ALTER ROLE cannot take a bind parameter, so the password is a quoted
// literal with single quotes doubled; cmd/db-init runs SET LOCAL standard_conforming_strings = on first, so
// backslashes are literal.
// Statements panics if Validate(roles) fails; call Validate first.
func Statements(roles map[string]string) []string {
	if err := Validate(roles); err != nil {
		panic("dbinit: " + err.Error())
	}
	out := make([]string, 0, 6*len(Services))
	for _, s := range Services {
		role := "svc_" + s.Key
		out = append(out,
			"CREATE SCHEMA IF NOT EXISTS "+s.Schema,
			"DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='"+role+"') THEN CREATE ROLE "+role+" LOGIN; END IF; END $$",
			"ALTER ROLE "+role+" WITH PASSWORD "+quoteLiteral(roles[s.Key]),
			"GRANT USAGE, CREATE ON SCHEMA "+s.Schema+" TO "+role,
			"ALTER DEFAULT PRIVILEGES IN SCHEMA "+s.Schema+" GRANT ALL ON TABLES TO "+role,
			"REVOKE ALL ON SCHEMA "+s.Schema+" FROM PUBLIC",
		)
	}
	return out
}

func quoteLiteral(s string) string { return "'" + strings.ReplaceAll(s, "'", "''") + "'" }
