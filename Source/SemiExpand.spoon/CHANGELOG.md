# Changelog

## 0.9.0 (soft launch)

First public version.

- `;name` expansions from plain-text files in `~/.config/semiexpand/` (or
  `$XDG_CONFIG_HOME/semiexpand`, or the `directory` setting), reloaded on save.
- Expands as soon as what you typed starts only one abbreviation; typing on the rest of the
  name is swallowed. Names shared by several abbreviations wait for space or a pause.
- Space opens a searchable picker (by name, text or section) with preview tiles, following
  the system light/dark appearance.
- Several files with their own prefix (`;`, `;;`, …); an optional `personal.md` for `;;`.
- Expansions are pasted with the clipboard restored and the temporary copy marked
  transient for clipboard managers.
