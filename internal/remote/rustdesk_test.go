package remote

import (
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

func TestUserHelperAppPath(t *testing.T) {
	p, err := userHelperAppPath()
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasSuffix(p, "Applications/LunaRemote.app") {
		t.Fatalf("unexpected path %q", p)
	}
}
