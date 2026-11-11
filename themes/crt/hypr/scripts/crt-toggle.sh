#!/bin/sh
# Toggle the CRT screen shader on/off for this session.
shader="$HOME/.config/hypr/shaders/crt.frag"
current="$(hyprctl getoption decoration:screen_shader -j | jq -r '.str')"
if [ -n "$current" ] && [ "$current" != "[[EMPTY]]" ]; then
    hyprctl keyword decoration:screen_shader "[[EMPTY]]"
else
    hyprctl keyword decoration:screen_shader "$shader"
fi
