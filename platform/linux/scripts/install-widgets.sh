#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
linux_dir=$(cd -- "$script_dir/.." && pwd)
install_plasma=false
install_gnome=false
prefix=

usage() {
  cat <<'EOF'
Usage: install-widgets.sh [--plasma] [--gnome] [--prefix PATH]

Without a selection, both widgets are installed. With no prefix, installation
uses XDG_DATA_HOME (normally ~/.local/share). A prefix such as /usr stages a
system installation under PREFIX/share.
EOF
}

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
      usage
      exit 0
      ;;
    *)
      usage >&2
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

plasma_source="$linux_dir/plasma/org.dayman.DayMan"
gnome_source="$linux_dir/gnome/dayman@dayman.app"

# AppImages place the sources beside this installer instead of preserving the
# repository layout.
if [[ ! -d "$plasma_source" && -d "$script_dir/widgets/plasma/org.dayman.DayMan" ]]; then
  plasma_source="$script_dir/widgets/plasma/org.dayman.DayMan"
fi
if [[ ! -d "$gnome_source" && -d "$script_dir/widgets/gnome/dayman@dayman.app" ]]; then
  gnome_source="$script_dir/widgets/gnome/dayman@dayman.app"
fi

if $install_plasma; then
  destination="$data_home/plasma/plasmoids/org.dayman.DayMan"
  [[ -f "$plasma_source/metadata.json" ]] || {
    echo "Plasma widget source is missing: $plasma_source" >&2
    exit 1
  }
  mkdir -p "$(dirname -- "$destination")"
  rm -rf -- "$destination"
  cp -a -- "$plasma_source" "$destination"
  echo "Installed Plasma widget in $destination"
fi

if $install_gnome; then
  destination="$data_home/gnome-shell/extensions/dayman@dayman.app"
  [[ -f "$gnome_source/metadata.json" ]] || {
    echo "GNOME extension source is missing: $gnome_source" >&2
    exit 1
  }
  mkdir -p "$(dirname -- "$destination")"
  rm -rf -- "$destination"
  cp -a -- "$gnome_source" "$destination"
  echo "Installed GNOME extension in $destination"
fi

echo "Widgets installed. Add DayMan Clock in Plasma or enable dayman@dayman.app in GNOME Extensions."
