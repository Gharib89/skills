package seed

import "os"

// Remove drops the error errcheck reports.
func Remove() {
	os.Remove("x")
}
