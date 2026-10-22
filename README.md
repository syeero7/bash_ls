# Bash Language Server

A language server for bash

## Features

- Find references
- Go to definition
- Completion
- Hover

## Usage

Download [latest release](https://github.com/syeero7/bash_ls/releases/latest)

Extract help messages (optional)

```bash
# download the script
curl -O https://raw.githubusercontent.com/syeero7/bash_ls/main/extract_help.bash

# edit the script (add/remove commands)
# default script include bash builtins and other common commands

# make it executable
chmod +x ./extract_help.bash

# run the script
./extract_help.bash <output_path>
# default output path is ./command_help.jsonl
```

### Neovim

```lua
    vim.lsp.config("bash_ls", {
        cmd = {
          "/path/to/bash_ls",
          "--log-file","/path/to/log_file", -- optional
          "--command-help", "/path/to/command_help.jsonl" -- optional
        },
        filetypes = {
          "bash",
          "sh"
        },
    })

    vim.lsp.enable("bash_ls")
```

## Build from Source

Install [Zig](https://ziglang.org/intro/getting-started/) v0.16

```bash
# clone the repository
git clone https://github.com/syeero7/bash_ls
cd bash_ls

# native build
zig build -Doptimize=ReleaseFast

# build for multiple targets. check build.zig
zig build -Doptimize=ReleaseFast -Dmulti-targets
```

### Run Tests

```bash
zig build test --summary all
```
