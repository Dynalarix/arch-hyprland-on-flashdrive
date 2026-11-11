if status is-interactive
    set -g fish_greeting

    # Vim key bindings: Esc for normal mode, i/a to insert, etc.
    set -g fish_key_bindings fish_vi_key_bindings
    # Cursor shows the mode: block in normal, bar in insert, underline for replace.
    set -g fish_cursor_default block
    set -g fish_cursor_insert line
    set -g fish_cursor_replace_one underscore
    set -g fish_cursor_visual block
    # Ctrl+F accepts the gray autosuggestion in insert mode too.
    bind -M insert \cf accept-autosuggestion

    command -q zoxide; and zoxide init fish | source
    command -q starship; and starship init fish | source
    alias ls 'eza --group-directories-first'
    alias ll 'eza -l --git --group-directories-first'
    alias la 'eza -la --git --group-directories-first'
end
