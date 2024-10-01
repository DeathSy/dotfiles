#!/bin/bash

case "$SENDER" in
"front_app_switched")
	sketchybar --set "$NAME" label="$INFO"
	;;
esac
