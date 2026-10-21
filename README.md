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
# default output path is current directory
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
