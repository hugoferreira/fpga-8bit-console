#!/bin/sh

printf '%s\n' \
    'laasm: deprecated; use inlay (legacy support requires a separate removal change)' \
    >&2

case $0 in
    */*) launcher_dir=${0%/*} ;;
    *) launcher_dir=. ;;
esac

exec "$launcher_dir/../inlay/inlay" "$@"
