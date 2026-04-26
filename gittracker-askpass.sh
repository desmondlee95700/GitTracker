#!/bin/sh
case "$1" in
  *Username*) printf "%s" "$GITTRACKER_GH_USER" ;;
  *) printf "%s" "$GITTRACKER_GH_TOKEN" ;;
esac