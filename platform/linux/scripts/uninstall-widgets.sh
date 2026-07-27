#!/usr/bin/env bash
set -euo pipefail

install_plasma=false
install_gnome=false
prefix=

while (($#)); do
  case "$1" in
    --plasma)
      install_plasma=true
      ;;
    --gnome)
      install_gnome=true
      ;;
    --prefix)
      shift
      prefix=${1:?--prefix requires a path}
      ;;
    --help|-h)
      echo "Usage: $0 [--plasma] [--gnome] [--prefix PATH]"
      exit 0
      ;;
    *)
      echo "Usage: $0 [--plasma] [--gnome] [--prefix PATH]" >&2
      exit 2
      ;;
  esac
  shift
done

if ! $install_plasma && ! $install_gnome; then
  install_plasma=true
  install_gnome=true
fi

if [[ -n "$prefix" ]]; then
  data_home=${prefix%/}/share
else
  data_home=${XDG_DATA_HOME:-"$HOME/.local/share"}
fi

if $install_plasma; then
  target="$data_home/plasma/plasmoids/org.dayman.DayMan"
  if [[ -d "$target" ]]; then
    rm -rf -- "$target"
    echo "Removed $target"
  fi
fi

if $install_gnome; then
  target="$data_home/gnome-shell/extensions/dayman@dayman.app"
  if [[ -d "$target" ]]; then
    rm -rf -- "$target"
    echo "Removed $target"
  fi
fi
