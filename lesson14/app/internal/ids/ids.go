// Package ids makes short random resource ids such as ord-1a2b3c4d.
package ids

import (
	"crypto/rand"
	"encoding/hex"
)

// New returns prefix + 8 random hex characters.
func New(prefix string) string {
	b := make([]byte, 4)
	_, _ = rand.Read(b) // crypto/rand.Read never fails on supported platforms
	return prefix + hex.EncodeToString(b)
}
