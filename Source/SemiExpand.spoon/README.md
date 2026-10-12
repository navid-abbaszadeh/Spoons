# SemiExpand.spoon

Text expansions for [Hammerspoon](https://www.hammerspoon.org): type `;smile` and get 😊,
`;sig` and get your signature. Abbreviations live in plain-text files you can keep in git,
and a searchable picker helps when you don't remember a name.

- **Expands as you type**: as soon as what you typed starts only one abbreviation
  (`;keyb` → ⌨️). If you keep typing the rest of the name out of habit, it's swallowed.
- **Shared starts wait**: `;pi` doesn't expand while `;pin` and `;pizza` also exist; press
  space to expand `;pi` or pick from a list.
- **Picker**: space after a partial name that matches several abbreviations opens a
  searchable list, by name, text or section heading, with a preview tile for each entry.
- **Several files with their own prefix**: e.g. `;name` from one file and `;;name` from a
  second one for personal data, kept out of the other's picker.
- **Works in any app**, including terminals and editors like vim: the expansion is pasted
  where you typed it.

## Installation

Download [SemiExpand.spoon.zip](https://github.com/navid-abbaszadeh/Spoons/raw/main/Spoons/SemiExpand.spoon.zip),
unzip it and double-click `SemiExpand.spoon` (or copy it to `~/.hammerspoon/Spoons/`).

Or with [SpoonInstall](https://www.hammerspoon.org/Spoons/SpoonInstall.html), which
downloads it the first time your config runs:

```lua
hs.loadSpoon("SpoonInstall")
spoon.SpoonInstall.repos.nvd = {
  url = "https://github.com/navid-abbaszadeh/Spoons",
  desc = "navid-abbaszadeh's Spoons",
  branch = "main",
}
spoon.SpoonInstall:andUse("SemiExpand", {
  repo = "nvd",
  config = { pauseSeconds = 2 }, -- optional, any of the settings below
  start = true,
})
```

`andUse` installs, configures and starts it in one call. To install it in one place and
set it up in another (e.g. one file that installs all your Spoons), make SpoonInstall wait
for the download, then load it as in Quick start:

```lua
hs.loadSpoon("SpoonInstall")
spoon.SpoonInstall.use_syncinstall = true -- wait, so hs.loadSpoon below finds it
spoon.SpoonInstall.repos.nvd = { … as above … }
if not hs.spoons.isInstalled("SemiExpand") then
  spoon.SpoonInstall:updateRepo("nvd")
  spoon.SpoonInstall:installSpoonFromRepo("SemiExpand", "nvd")
end

-- later, e.g. in another file
hs.loadSpoon("SemiExpand")
spoon.SemiExpand.pauseSeconds = 2
spoon.SemiExpand:start()
```

Without `use_syncinstall`, SpoonInstall downloads in the background, so on the first run
`hs.loadSpoon` would come before the download finishes. SpoonInstall only downloads a Spoon
that isn't installed yet: to update, delete `Spoons/SemiExpand.spoon` and reload.

Hammerspoon needs **Accessibility** access (System Settings → Privacy & Security).

## Quick start

Create `~/.config/semiexpand/expansions.md` (copy `example.md` from the Spoon to start),
then in `~/.hammerspoon/init.lua`:

```lua
hs.loadSpoon("SemiExpand")
spoon.SemiExpand:start()
```

Type `;smile`.

## Where the files live

Everything is in one folder: `$XDG_CONFIG_HOME/semiexpand` if that variable is set for
Hammerspoon, otherwise `~/.config/semiexpand`:

| File | Typed as | |
|---|---|---|
| `expansions.md` | `;name` | your expansions |
| `personal.md` | `;;name` | optional, e.g. for your email, phone or address; kept out of the `;` picker, and skipped silently if it doesn't exist |

Hammerspoon is started by macOS, not from your shell, so it only sees `XDG_CONFIG_HOME` if
it's set for GUI apps (e.g. `launchctl setenv XDG_CONFIG_HOME …`). To use another folder,
set `spoon.SemiExpand.directory = "~/somewhere/semiexpand"`; for other file names or more
files, see `sets` below.

> **Don't name your own config file `semiexpand.lua`.** macOS file names ignore case, so
> `hs.loadSpoon("SemiExpand")` would load that file instead of the Spoon.

## The expansions file

One entry per line:

```
// a comment
# Faces                        ← a section heading, searchable in the picker
smile "😊"
joy lol "😂"                   ← several names for the same text
sig "Best regards,\nMe"        ← \n newline, \t tab, \" quote, \\ backslash
```

- Names are written **without** the prefix; the file's prefix is added (`smile` → `;smile`).
- Names are case-sensitive (`delta` and `Delta` are different) and can contain symbols
  (`->`, `a*`, `o:`).
- Anything after `(` or `:` in a heading is left out of the section name, so headings can
  carry notes: `# Greek letters (Vim digraphs)`.
- Saved changes are picked up automatically.

## How expansion works

| You type | Result |
|---|---|
| a complete name that no other name starts with (`;done`) | expands immediately |
| a start that only one name has, from 2 letters on (`;keyb`) | expands immediately; typing on the rest of the name (`oard`) is swallowed |
| a name or start shared by several (`;pi` with `;pig`, `;pin`) | waits |
| … then space, on a complete name (`;pi␣`) | expands it |
| … then space, on a start of just one name (`;handsh␣`) | expands that one |
| … then space, on anything else with matches (`;han␣`) | opens the picker; exact match first, then names starting with it, names containing it, and entries whose section contains it |
| … then a short pause | a complete name expands; anything else is left as typed |
| `;` then Esc, then text (`;⎋done`) | typed literally |

Expanded text is pasted (the clipboard is restored afterwards and the temporary copy is
marked transient, so clipboard managers skip it).

## Settings

Set these before `:start()`:

| Setting | Default | |
|---|---|---|
| `directory` | `$XDG_CONFIG_HOME/semiexpand` or `~/.config/semiexpand` | the folder with the files |
| `sets` | `expansions.md` (`;`), `personal.md` (`;;`, optional) | `{ file, prefix, optional }` per file; a relative `file` is inside `directory`; prefixes are made of the trigger (`;`, `;;`, …), and a word is looked up only in the file with the longest matching prefix; a missing optional file is skipped silently |
| `trigger` | `";"` | the character that starts a name |
| `pickerKey` | `" "` | expands or opens the picker after a partial name |
| `minUniqueChars` | `2` | shorter starts only expand when they are a complete name |
| `pauseSeconds` | `1` | pause that ends a word |
| `restSeconds` | `2` | how long typing on the rest of an early-expanded name is swallowed |
| `alertOnReload` | `true` | alert when a file is reloaded |
| `picker` | width 36, 9 rows, tiles on | `{ width, rows, placeholder, matchColor, tiles }` |

### Adding a file with its own prefix

Say you want work snippets in their own file, typed as `;;;name`:

1. Create `work.md` next to `expansions.md`, in the same format:

   ```
   # Work
   standup "Yesterday:\nToday:\nBlockers:"
   addr "Example Corp, 1 Main Street"
   ```

2. List it in `sets`. Setting `sets` replaces the defaults, so keep the two files you
   already use:

   ```lua
   hs.loadSpoon("SemiExpand")
   spoon.SemiExpand.sets = {
     { file = "expansions.md", prefix = ";" },
     { file = "personal.md", prefix = ";;", optional = true },
     { file = "work.md", prefix = ";;;", optional = true },
   }
   spoon.SemiExpand:start()
   ```

   With SpoonInstall, pass the same list as `config = { sets = { … } }` to `andUse`.

3. Reload Hammerspoon. Now:

   | You type | Result |
   |---|---|
   | `;;;standup` | expands from `work.md` |
   | `;;;` then space, at the start of a word | opens the picker with only the `work.md` entries |
   | `;standup` or `;;standup` | nothing: `;` only looks in `expansions.md`, `;;` only in `personal.md` |

   Names only have to be unique within their file: `;addr` and `;;;addr` can expand to
   different texts. `optional = true` means Hammerspoon starts fine while `work.md` doesn't
   exist yet; once you create it, it's picked up without a reload.

### Prefixes

Every prefix is the trigger character repeated: `;`, `;;`, `;;;` and so on, as many files
as you like. A name is looked up only in the file with the longest prefix that matches:
`;;;standup` belongs to `work.md` even though it also starts with `;` and `;;`.

Prefixes can't mix characters. `trigger = "?"` works, but then every prefix must be `?`,
`??`, …; `;` for one file and `?` for another isn't possible, because the Spoon watches
for one trigger character. A prefix that isn't made of the trigger stops `:start()` with
an error.

## Limitations

- While macOS **secure input** is on (password fields, some password managers, Terminal's
  "Secure Keyboard Entry"), keystrokes can't be seen, so nothing expands.
- Only the keys typed since the last click, cursor key or shortcut are considered, so a name
  is recognised when typed in one go.

## Development

From the root of the [Spoons repo](https://github.com/navid-abbaszadeh/Spoons):

```sh
make test   # unit tests for parser.lua and matcher.lua (plain Lua 5.4+)
make docs   # regenerate docs.json from the --- doc comments in init.lua (needs Hammerspoon)
make zip    # rebuild Spoons/SemiExpand.spoon.zip
```

What the unit tests don't cover, to try by hand after changes:

1. `;done` expands; `;do` alone doesn't (if `;dog` exists); `;do␣` opens the picker.
2. In the picker: typing filters, arrows move, Enter inserts, Esc leaves the text alone.
3. `;keyboard` typed in full gives one ⌨️ and no leftover letters.
4. With a `;;` set: `;;name` expands from that file only, and `;name` never shows its entries.
5. Saving the expansions file shows the reload alert and the change works right away;
   creating `personal.md` while Hammerspoon runs makes `;;name` work without a reload.
6. In a terminal (shell prompt and vim's insert mode): `;done` expands and `;do␣` opens the
   picker, which inserts the choice there.

## License

MIT, see [LICENSE](LICENSE).
