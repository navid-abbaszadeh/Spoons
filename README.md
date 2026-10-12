# Spoons

[Hammerspoon](https://www.hammerspoon.org) Spoons by Navid Abbaszadeh.

| Spoon | Version | |
|---|---|---|
| [SemiExpand](Source/SemiExpand.spoon/README.md) | 0.9.0 | Text expansions typed as `;name` from plain-text files, with a searchable picker ([settings](Source/SemiExpand.spoon/README.md#settings)) |

## Installing

With [SpoonInstall](https://www.hammerspoon.org/Spoons/SpoonInstall.html):

```lua
hs.loadSpoon("SpoonInstall")
spoon.SpoonInstall.repos.nvd = {
  url = "https://github.com/navid-abbaszadeh/Spoons",
  desc = "navid-abbaszadeh's Spoons",
  branch = "main",
}
spoon.SpoonInstall:andUse("SemiExpand", { repo = "nvd", start = true })
```

Or download a zip from [Spoons/](Spoons), unzip it and double-click the `.spoon` folder.
Each Spoon has its own README with its setup and settings, linked from the table above.

## Layout

- `Source/<Name>.spoon`: the source, with its README, tests and docs
- `Spoons/<Name>.spoon.zip`: what SpoonInstall downloads
- `docs/docs.json`: the combined API docs SpoonInstall reads to find the Spoons

`make test` runs the tests, `make docs` regenerates the docs (needs Hammerspoon's `hs`
command), `make zip` rebuilds the zips, and `make all` does all three before a release.

## License

MIT, see [LICENSE](LICENSE).
