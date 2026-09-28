package seed

import "fmt"

// Bad hands %d a string.
func Bad() string {
	return fmt.Sprintf("%d", "x")
}
