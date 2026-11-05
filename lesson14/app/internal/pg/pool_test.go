package pg

import (
	"strings"
	"testing"
)

func setDBEnv(t *testing.T, env map[string]string) {
	t.Helper()
	for _, k := range []string{"DB_HOST", "DB_PORT", "DB_NAME", "DB_USER", "DB_PASSWORD", "DB_SSLMODE", "DB_SCHEMA"} {
		t.Setenv(k, env[k])
	}
}

func TestConfigFromEnv(t *testing.T) {
	full := map[string]string{
		"DB_HOST": "db.internal", "DB_PORT": "6543", "DB_NAME": "shop",
		"DB_USER": "svc_order", "DB_PASSWORD": "p@ss:/word", "DB_SCHEMA": "orders",
	}
	cases := map[string]struct {
		override map[string]string
		wantErr  string
		wantTLS  bool
	}{
		"all set, sslmode defaults to require": {wantTLS: true},
		"sslmode disable":                      {override: map[string]string{"DB_SSLMODE": "disable"}},
		"missing schema":                       {override: map[string]string{"DB_SCHEMA": ""}, wantErr: "DB_SCHEMA"},
	}
	for name, c := range cases {
		t.Run(name, func(t *testing.T) {
			env := map[string]string{}
			for k, v := range full {
				env[k] = v
			}
			for k, v := range c.override {
				env[k] = v
			}
			setDBEnv(t, env)
			cfg, err := ConfigFromEnv()
			if c.wantErr != "" {
				if err == nil || !strings.Contains(err.Error(), c.wantErr) {
					t.Fatalf("err = %v, want one naming %s", err, c.wantErr)
				}
				return
			}
			if err != nil {
				t.Fatalf("ConfigFromEnv: %v", err)
			}
			cc := cfg.ConnConfig
			if cc.Host != "db.internal" || cc.Port != 6543 || cc.Database != "shop" || cc.User != "svc_order" || cc.Password != "p@ss:/word" {
				t.Errorf("conn = %s:%d/%s as %s (password %q)", cc.Host, cc.Port, cc.Database, cc.User, cc.Password)
			}
			if got := cc.RuntimeParams["search_path"]; got != "orders" {
				t.Errorf("search_path = %q, want orders", got)
			}
			if (cc.TLSConfig != nil) != c.wantTLS {
				t.Errorf("TLS = %v, want %v", cc.TLSConfig != nil, c.wantTLS)
			}
		})
	}
}

func TestAdminConfigFromEnv_OverridesUserAndNeedsNoSchema(t *testing.T) {
	setDBEnv(t, map[string]string{"DB_HOST": "db.internal", "DB_NAME": "shop", "DB_USER": "svc_x", "DB_PASSWORD": "svc-pw", "DB_SSLMODE": "disable"})
	cc, err := AdminConfigFromEnv("shop_admin", "admin-pw")
	if err != nil {
		t.Fatalf("AdminConfigFromEnv: %v", err)
	}
	if cc.User != "shop_admin" || cc.Password != "admin-pw" || cc.Host != "db.internal" || cc.Port != 5432 || cc.Database != "shop" {
		t.Errorf("conn = %s:%d/%s as %s (password %q)", cc.Host, cc.Port, cc.Database, cc.User, cc.Password)
	}
	if _, ok := cc.RuntimeParams["search_path"]; ok {
		t.Errorf("search_path set for the admin connection: %q", cc.RuntimeParams["search_path"])
	}
}

func TestAdminConfigFromEnv_SSLModeDefaultsToRequire(t *testing.T) {
	setDBEnv(t, map[string]string{"DB_HOST": "db.internal", "DB_NAME": "shop"}) // DB_SSLMODE unset
	cc, err := AdminConfigFromEnv("shop_admin", "admin-pw")
	if err != nil {
		t.Fatalf("AdminConfigFromEnv: %v", err)
	}
	if cc.TLSConfig == nil {
		t.Error("TLSConfig = nil, want TLS (sslmode=require) when DB_SSLMODE is unset")
	}
}
