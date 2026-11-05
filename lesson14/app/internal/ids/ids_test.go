package ids

import (
	"regexp"
	"testing"
)

func TestNew_PrefixPlus8Hex(t *testing.T) {
	shape := regexp.MustCompile(`^ord-[0-9a-f]{8}$`)
	a, b := New("ord-"), New("ord-")
	if !shape.MatchString(a) || !shape.MatchString(b) {
		t.Errorf("ids = %q, %q; want ord-<8 hex>", a, b)
	}
	if a == b {
		t.Errorf("two ids are equal: %q", a)
	}
}
