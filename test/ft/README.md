# The integration tier

7 tests that ask a real Factorio what it actually did, on top of
[factorio-test](https://mods.factorio.com/mod/factorio-test). Headless, no display.

```bash
npm install                    # once: fetches factorio-test-cli
test/ft/run.sh                 # the whole suite
test/ft/run.sh -v              # with the game's own log lines
test/ft/run.sh "reflection"    # only tests matching a Lua pattern
test/ft/run.sh -b              # stop at the first failure
```

`WM_FACTORIO` points at the game binary, `WM_FT_DATA` at the throwaway data directory the
run happens in (`~/.cache/world-mirror-factorio-test` by default, deliberately outside the
repo — the runner symlinks the mod under test into that directory's mods folder, so a data
directory inside the repo would make the repo contain itself). Two runs cannot share one
data directory.

The unit tier is separate: `test/run.sh` runs the busted specs in `test/spec` against
`lib/`, in thirty milliseconds, with no game at all. The coordinate arithmetic belongs
there. Anything about what the engine really does belongs here.

**One test is red on purpose.** A reflected chunk comes back with no decoratives, though
its master has them and the mod asks for them by name. That is a real outstanding bug,
noted for 2.1.2; the test is left failing rather than deleted so it turns green when the
bug is fixed.

## How it fits together

- `control.lua` registers the fixtures, guarded on both `factorio-test` and `wm-tests`
  being loaded. `wm-tests` is never published, so the hook can never fire on a player's
  machine — `info.json` keeps `test/` out of the package.
- `test/ft/wm-tests` holds no prototypes. It is the marker that says "this is a test run".
- `is_a_world` is global so the fixtures drive the real predicate rather than
  reimplementing it.

## Two things about the ground

**The save this suite runs from is a lab-tile world.** `lab-dark-1` and `lab-dark-2`, no
entities, no decoratives, for as far as chunks generate. Nothing can be asked there about
cloning a tree — and, less obviously, nothing reliable can be asked about tiles either: a
reflection written 32 tiles off still matched, because one patch of checkerboard looks
much like another. Every fixture about mirroring therefore runs on `world.terrain()`,
which creates Vulcanus: a real planet, so the mod treats it as a world, with terrain a
wrong answer cannot accidentally agree with.

**Nothing here asks the mod where it put something.** `world.reflection_of` writes the
reflection formula out again rather than calling `lib.mirror`. Borrowing the code under
test to compute the expected answer agrees with any answer it gives: dropping the chunk
width from the reflection passed every fixture until this stopped borrowing it. The same
goes for the guard fixture, which checks the master chunk was never generated rather than
only that tiles survived — without the guard the mod blanks the chunk, fetches its master
and copies it back, leaving tiles that look untouched.

**A chunk can only be used once.** Generating a master writes its reflection, and there is
no undoing that, so `world.claim()` hands out chunks that neither the save nor an earlier
fixture has generated, walking a grid rather than a line — the strip along `y = 0` turned
out to hold nothing worth cloning for a dozen chunks running.
