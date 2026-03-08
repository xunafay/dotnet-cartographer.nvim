# dotnet-cartographer.nvim

A .NET solution explorer for Neovim build on top of the snacks.nvim explorer.

This plugin is in early development and still has issues/missing features, see the [Known Issues](#known-issues) and [Roadmap](#roadmap) sections below for details.

## Why

Sometimes the projects in a .NET solutions do not map well to the folder structure on disk, which makes it hard to navigate the solution with a file explorer. This plugin provides a solution explorer that shows the projects and files in the solution as they are defined in the .slnx file, regardless of their location on disk.

## Requirements

- Neovim 0.11 or higher
- snacks.nvim

## Installation

### Lazy.nvim

```lua
{
    "xunafay/dotnet-cartographer.nvim",
    dependencies = {
        "folke/snacks.nvim",
    },
    opts = {
        -- opts
    },
    config = function()
        -- register the cartographer source with snacks.nvim
        require('dotnet-cartographer').setup()

        -- opens the solution picker when the plugin is loaded
        -- If only one solution file is found, it will be selected without showing the picker
        require('dotnet-cartographer').pick_solution()
    end,
    keys = {
        {
          '<leader>se',
          function()
            require('snacks').picker.pick {
              source = 'cartographer',
              title = 'Solution Explorer',
            }
          end,
          desc = '[S]olution [E]xplorer',
        },
    },
}
```

## Known Issues

- Only supports .slnx files (migrate your .sln file with `dotnet sln migrate`)
- File operations (create, delete, rename) are not yet supported
- Searching for files results in an error
- .gitignored files are still shown in the explorer
- No way to pass options to the underlying snacks picker (e.g. to enable preview)

## Roadmap

- [ ] Add support for .sln files
- [ ] Implement file operations (create, delete, rename)
- [ ] File search functionality
- [ ] Add commands to build folders/projects/solution from the explorer
- [ ] Support gitsigns
- [ ] Support diagnosticts
- [ ] Integrate with roslyn.nvim
- [ ] Snacks file picker & grep but scoped to the current solution

## Contributing

Contributions are welcome! Please open an issue or submit a pull request if you have any ideas or improvements.
This plugin was initially for personal use, but I would be happy to see it grow and be useful for others in the Neovim community.
A lot is still missing/hardcoded, so any help is appreciated.
