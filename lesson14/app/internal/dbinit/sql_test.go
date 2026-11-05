package dbinit

import (
	"strings"
	"testing"
)

var roles = map[string]string{"user": "pw-u", "product": "pw-p", "order": "pw-o", "payment": "pw-y"}

func TestStatements_OneSchemaPerService(t *testing.T) {
	stmts := Statements(roles)
	pairs := [][3]string{{"user", "users", "pw-u"}, {"product", "products", "pw-p"}, {"order", "orders", "pw-o"}, {"payment", "payments", "pw-y"}}

	var want []string
	for _, p := range pairs {
		svc, schema, pw := p[0], p[1], p[2]
		want = append(want,
			"CREATE SCHEMA IF NOT EXISTS "+schema,
			"DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='svc_"+svc+"') THEN CREATE ROLE svc_"+svc+" LOGIN; END IF; END $$",
			"ALTER ROLE svc_"+svc+" WITH PASSWORD '"+pw+"'",
			"GRANT USAGE, CREATE ON SCHEMA "+schema+" TO svc_"+svc,
			"ALTER DEFAULT PRIVILEGES IN SCHEMA "+schema+" GRANT ALL ON TABLES TO svc_"+svc,
			"REVOKE ALL ON SCHEMA "+schema+" FROM PUBLIC",
		)
	}
	if strings.Join(stmts, "\n") != strings.Join(want, "\n") {
		t.Fatalf("statements =\n%s\nwant\n%s", strings.Join(stmts, "\n"), strings.Join(want, "\n"))
	}

	// No cross-grants: every statement naming a role names only that role's own schema.
	for _, s := range stmts {
		for _, p := range pairs {
			if strings.Contains(s, "TO svc_"+p[0]) && !strings.Contains(s, "SCHEMA "+p[1]+" ") {
				t.Errorf("cross-grant: %s", s)
			}
		}
	}
}

func TestStatements_EscapesQuoteInPassword(t *testing.T) {
	r := map[string]string{"user": "it's", "product": "a''b", "order": `back\slash`, "payment": "x"}
	stmts := Statements(r)
	for _, want := range []string{
		"ALTER ROLE svc_user WITH PASSWORD 'it''s'",
		"ALTER ROLE svc_product WITH PASSWORD 'a''''b'",
		`ALTER ROLE svc_order WITH PASSWORD 'back\slash'`,
	} {
		found := false
		for _, s := range stmts {
			found = found || s == want
		}
		if !found {
			t.Errorf("missing %s in\n%s", want, strings.Join(stmts, "\n"))
		}
	}

	bad := map[string]map[string]string{
		"NUL in password": {"user": "a\x00b", "product": "x", "order": "x", "payment": "x"},
		"missing payment": {"user": "x", "product": "x", "order": "x"},
		"empty password":  {"user": "", "product": "x", "order": "x", "payment": "x"},
	}
	for name, r := range bad {
		if err := Validate(r); err == nil {
			t.Errorf("Validate(%s): want error", name)
		}
		func() {
			defer func() {
				if recover() == nil {
					t.Errorf("Statements(%s): want panic", name)
				}
			}()
			Statements(r)
		}()
	}
	if err := Validate(roles); err != nil {
		t.Errorf("Validate(valid) = %v", err)
	}
}
