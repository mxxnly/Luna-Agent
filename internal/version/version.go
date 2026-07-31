package version

// Version is overwritten at link time via -ldflags.
var Version = "dev"

// Commit is overwritten at link time via -ldflags.
var Commit = "none"
