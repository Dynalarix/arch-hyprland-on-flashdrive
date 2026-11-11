if status is-interactive
    set -g fish_greeting
    command -q zoxide; and zoxide init fish | source
    command -q starship; and starship init fish | source
    alias ls 'eza --group-directories-first'
    alias ll 'eza -l --git --group-directories-first'
    alias la 'eza -la --git --group-directories-first'
end
