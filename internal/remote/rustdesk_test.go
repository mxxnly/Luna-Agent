package remote

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestWriteConfigPathsNonEmpty(t *testing.T) {
	paths := configPaths()
	if len(paths) == 0 {
		t.Fatal("expected at least one config path")
	}
}

func TestCurrentDefault(t *testing.T) {
	Disable()
	st := Current()
	if st.Enabled {
		t.Fatal("expected disabled after Disable")
	}
}

func TestPatchIdentityPassword(t *testing.T) {
	got, err := patchIdentityPassword("", "Abc12345")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(got, "password = 'Abc12345'") {
		t.Fatalf("missing password: %q", got)
	}
	if !strings.Contains(got, "salt = '") {
		t.Fatalf("missing salt: %q", got)
	}

	existing := "enc_id = 'x'\npassword = ''\nsalt = 'fixedsalt'\nkey_confirmed = true\n"
	got, err = patchIdentityPassword(existing, "NewPass99")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(got, "password = 'NewPass99'") {
		t.Fatalf("password not replaced: %q", got)
	}
	if !strings.Contains(got, "salt = 'fixedsalt'") {
		t.Fatalf("salt should be preserved: %q", got)
	}
	if strings.Count(got, "password =") != 1 {
		t.Fatalf("expected one password line: %q", got)
	}
}

func TestWritePermanentPasswordFile(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "RustDesk.toml")
	if err := os.WriteFile(path, []byte("password = ''\nsalt = 'abc'\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	body, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	next, err := patchIdentityPassword(string(body), "PanelPass1")
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(next), 0o600); err != nil {
		t.Fatal(err)
	}
	out, _ := os.ReadFile(path)
	if !strings.Contains(string(out), "password = 'PanelPass1'") {
		t.Fatalf("got %s", out)
	}
}
