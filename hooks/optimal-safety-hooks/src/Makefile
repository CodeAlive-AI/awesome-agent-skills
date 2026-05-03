.PHONY: build test fmt vet bench clean install watch

# Default target: build the binary in place. Run after editing any .go
# source so the next hook invocation picks up the change.
build:
	go build -o bash_guard.bin .

test:
	go test -count=1 ./...

vet:
	go vet ./...

fmt:
	gofmt -w .

bench:
	go test -run='^$$' -bench=. -benchmem ./...

clean:
	rm -f bash_guard.bin build.log

# Run install.sh from the parent directory.
install:
	../install.sh --shadow

# Auto-rebuild on .go save while the dev edits. Requires `entr`:
#     brew install entr
# Use this instead of a runtime build-on-stale wrapper.
watch:
	@if ! command -v entr >/dev/null; then \
		echo "entr not installed. brew install entr" >&2; exit 1; \
	fi
	ls *.go | entr -c go build -o bash_guard.bin .
