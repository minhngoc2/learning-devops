package config

import "testing"

func TestGet_FallsBackToDefault(t *testing.T) {
	t.Setenv("L14_SET", "value")
	t.Setenv("L14_EMPTY", "")
	if got := Get("L14_SET", "def"); got != "value" {
		t.Errorf("Get(set) = %q", got)
	}
	if got := Get("L14_EMPTY", "def"); got != "def" {
		t.Errorf("Get(empty) = %q, want default", got)
	}
}

func TestInt_InvalidFallsBackToDefault(t *testing.T) {
	cases := map[string]int{"7": 7, "": 3, "seven": 3}
	for raw, want := range cases {
		t.Setenv("L14_INT", raw)
		if got := Int("L14_INT", 3); got != want {
			t.Errorf("Int(%q) = %d, want %d", raw, got, want)
		}
	}
}

func TestMustGet_PanicsWhenMissing(t *testing.T) {
	t.Setenv("L14_MISSING", "")
	defer func() {
		if recover() == nil {
			t.Error("MustGet did not panic on a missing variable")
		}
	}()
	MustGet("L14_MISSING")
}
