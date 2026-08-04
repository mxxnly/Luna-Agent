package remote

import "testing"

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
