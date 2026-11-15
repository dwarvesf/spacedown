# Proof of Done, mcp-server

`spacedown mcp` starts a stdio MCP server (protocol 2025-11-25, answers 2025-06-18) with three tools: `render`, `shot`, `lint`. It runs as `osascript -l JavaScript assets/sd-mcp.js`, so users need nothing beyond macOS. Each tool runs `bin/spacedown` and reads its stdout contract and stderr. `lint` rides a new `--lint-json FILE` flag that makes the renderer write the Writing X-ray findings as JSON, with the app's settings applied.

## Green run

The `mcp` section drives the server over stdin with a scripted session (`tests/mcp-test.js`): initialize and version handshake, `tools/list`, each tool on a fixture, settings applied through a stored-settings plist, every kind of bad input, and the README config snippet `{"mcpServers": {"spacedown": {"command": "spacedown", "args": ["mcp"]}}}` started by its command name from `PATH`.

```
Command: bash tests/smoke.sh
Exit: 0
Output:
[mcp] stdio MCP server (tests/mcp-test.js)
  ok: mcp: lint maps findings to source lines (really on 6, dash and ticket on 8, long sentence on 10)
  ok: mcp: shot writes a PNG and returns its path
  ok: mcp: shot returns the wide-table and red-KaTeX WARN lines as structured warnings
  ok: mcp: the README config snippet {command: spacedown, args: [mcp]} starts a working server
smoke: all 192 passed
Verdict: PASS
```

```
Command: bash tests/smoke.sh --only mcp,cli,xray
Exit: 0
Output: smoke: all 65 passed
Verdict: PASS
```

## Negative control

The lint wiring broken (the renderer no longer writes the findings file), same `mcp` section, then restored:

```
Command: bash tests/smoke.sh --only mcp
Exit: 1
Output:
  FAIL: mcp: lint returns structured findings and text content that parses to the same object [... "lint failed: the renderer wrote no findings file" ...]
  FAIL: mcp: lint finds the filler word, dash, ticket ID and long sentence, each with rule, line, excerpt, message
  FAIL: mcp: lint maps findings to source lines (really on 6, dash and ticket on 8, long sentence on 10)
smoke: 20 passed, 8 FAILED
Result: RED as expected
```

```
Command: bash tests/smoke.sh --only mcp
Exit: 0
Output: smoke: all 28 passed
Verdict: PASS
```

## Notes

| Item | Detail |
|---|---|
| Protocol | The 2026-07-28 revision is stateless and has no `initialize`. The server pins 2025-11-25 and also serves `tools/list` and `tools/call` without a prior `initialize`. |
| Runtime | osascript JavaScript (JXA). `NSTask.waitUntilExit` and `NSFileHandle.closeFile` are not bridged, so the server polls `running` and uses `closeAndReturnError`. |
| Schemas | No top-level `oneOf` (some model APIs reject it); "exactly one of path or text" is checked in the server. |

## Rollback

Revert this squash commit. `spacedown mcp` then falls through to rendering a file named `mcp`, and `--lint-json` is an unknown flag again.
