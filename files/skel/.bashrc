# ~/.bashrc for the portable Arch system.
[[ $- != *i* ]] && return

HISTSIZE=10000
HISTFILESIZE=20000
HISTCONTROL=ignoreboth:erasedups
shopt -s histappend checkwinsize autocd globstar

# Tab completion for commands, git branches, pacman packages, etc.
if [[ -z ${BASH_COMPLETION_VERSINFO:-} && -r /usr/share/bash-completion/bash_completion ]]; then
    source /usr/share/bash-completion/bash_completion
fi
[[ -r /usr/share/fzf/key-bindings.bash ]] && source /usr/share/fzf/key-bindings.bash
[[ -r /usr/share/fzf/completion.bash ]]   && source /usr/share/fzf/completion.bash

command -v zoxide   >/dev/null && eval "$(zoxide init bash)"
command -v starship >/dev/null && eval "$(starship init bash)"

alias ls='eza --group-directories-first'
alias ll='eza -l --git --group-directories-first'
alias la='eza -la --git --group-directories-first'
alias cat='bat --paging=never --style=plain'
alias grep='grep --color=auto'
