// Package config reads settings from environment variables, so one image runs in compose and on ECS.
package config

import (
	"fmt"
	"os"
	"strconv"
)

// Get returns the variable, or def when it is unset or empty.
func Get(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

// MustGet returns the variable and panics when it is unset or empty; call it at startup only.
func MustGet(key string) string {
	v := os.Getenv(key)
	if v == "" {
		panic(fmt.Sprintf("config: required environment variable %s is not set", key))
	}
	return v
}

// Int returns the variable as an int, or def when it is unset, empty or not an integer.
func Int(key string, def int) int {
	n, err := strconv.Atoi(os.Getenv(key))
	if err != nil {
		return def
	}
	return n
}
