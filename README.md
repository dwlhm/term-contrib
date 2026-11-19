# term-contrib

What is built on Term's public surface only, outside Term: term programs and
clients. Nothing here reads Term's source; it uses the installed `term` and
[`docs/PROTOCOL.md`](https://github.com/dwlhm/term/blob/main/docs/PROTOCOL.md).
Term's own `make test` runs this repo's tests, so the two stay in step.

## Programs

Term programs for apps that are tedious to drive by hand, so that an agent
(or a script) uses an app with one command instead of typing into its TUI
with `term session send` and reading the screen back. Each one describes
itself: `term program ls` lists them, `term run <program> --help` says how to
use one, and `--json` prints what an agent can parse.

| Program | What it does |
|---|---|
| `agy` | asks the Antigravity CLI in a directory and prints its answer (`ask`), takes the requests sent to its session (`serve`), shows its state (`status`) |
| `fzf` | picks from fzf, or lists its matches, by a query: in a session that shows fzf (`--session`) or on a command's output (`-- <command…>`) |

## Install

```sh
mkdir -p ~/.config/term
ln -s ~/project/term-contrib ~/.config/term/programs
term program ls
```

Only the `.lua` files at the top are programs; `lib/` holds what they share
(`require "lib.fzf"`).

## agy

```sh
term run agy ask "why does the build fail?" [--dir ~/project] [--json]
term run agy serve                      # then: term session tell <id> "<prompt>"
term run agy status [--json]
```

`ask` uses the agy session already open in the directory (one a person is
working in, so the conversation goes on) or starts one. The prompt goes in
as a request: agy answers it itself by running `term session answer`, which
is what `ask` prints. While agy works the program holds the session's input:
a person's Esc or ^C there ends the turn (exit 4). When agy waits for a
person (trusting a folder, a permission it asks for), the session is handed
over: the person answers in the window, the turn goes on; nobody within
`--person` seconds is a timeout (exit 3).

In auto mode (`auto` in agy's status bar) agy runs `term session answer` without
asking; in a mode where it asks, that permission is handed over like any
other.

## fzf

```sh
term run fzf pick bet -- git branch --format='%(refname:short)'  # prints the branch
term run fzf list "" --json -- ls                                # everything fzf offers
term run fzf pick main --session 7                               # an fzf already showing
```

`--nth n` picks the nth match (1 is the best). No match exits 1.

## Exit codes

0 done · 1 failed · 2 bad arguments · 3 timed out · 4 refused (a person
stopped it, nobody listens) · 5 cancelled.

## Tests

```sh
tests/run.sh [path/to/term]
```

It checks every program, reads saved fzf screens (`tests/fixtures`, saved
with `term session snapshot <id> --save`) and drives a real fzf, all in a
session core of its own. agy is not run there: it needs a signed-in account;
try `term run agy ask "say pong"` in a scratch directory.
