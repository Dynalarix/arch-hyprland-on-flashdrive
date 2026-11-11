# ~/.zshrc for the portable Arch system.

HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt hist_ignore_dups hist_ignore_space share_history autocd

# Completion (zsh-completions adds many extra definitions).
autoload -Uz compinit && compinit
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'

bindkey -e
bindkey '^[[H' beginning-of-line
bindkey '^[[F' end-of-line
bindkey '^[[3~' delete-char

[[ -r /usr/share/fzf/key-bindings.zsh ]] && source /usr/share/fzf/key-bindings.zsh
[[ -r /usr/share/fzf/completion.zsh ]]   && source /usr/share/fzf/completion.zsh
[[ -r /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && \
    source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh

command -v zoxide   >/dev/null && eval "$(zoxide init zsh)"
command -v starship >/dev/null && eval "$(starship init zsh)"

alias ls='eza --group-directories-first'
alias ll='eza -l --git --group-directories-first'
alias la='eza -la --git --group-directories-first'
alias cat='bat --paging=never --style=plain'
alias grep='grep --color=auto'

# Must be sourced last.
[[ -r /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && \
    source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
