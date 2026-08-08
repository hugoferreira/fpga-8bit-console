#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$root"

mkdir -p build/inlay/portable build/inlay/cc65

forbidden='malloc|calloc|realloc|free|fopen|fclose|popen|pclose|system|getenv|setlocale|json'
core="tools/inlay/inlay_workspace.c tools/inlay/inlay_describe.c \
tools/inlay/inlay_declare.c tools/inlay/inlay_layout.c \
tools/inlay/inlay_expression.c tools/inlay/inlay_tables.c \
tools/inlay/inlay_operations.c tools/inlay/inlay_invoke.c \
tools/inlay/inlay_emit.c tools/inlay/inlay_target.c"

if grep -En "$forbidden" $core \
    tools/inlay/inlay_modules.c tools/inlay/inlay.h \
    tools/inlay/inlay_internal.h; then
    echo "Inlay portability: forbidden host dependency in semantic core" >&2
    exit 1
fi

for unit in $core tools/inlay/inlay_modules.c; do
    cc -std=c89 -pedantic -Wall -Wextra -Werror \
        -c "$unit" -o "build/inlay/portable/$(basename "$unit" .c).o"
done

cc -std=c89 -pedantic -Wall -Wextra -Werror \
    -fsanitize=undefined -fno-omit-frame-pointer \
    $core tools/inlay/test_inlay.c \
    -o build/inlay/portable/test_inlay_ubsan
build/inlay/portable/test_inlay_ubsan

cc -std=c89 -pedantic -Wall -Wextra -Werror \
    -fsanitize=undefined -fno-omit-frame-pointer \
    $core tools/inlay/inlay_modules.c \
    tools/inlay/test_modules.c \
    -o build/inlay/portable/test_modules_ubsan
build/inlay/portable/test_modules_ubsan

cc -std=c99 -pedantic -Wall -Wextra -Werror \
    $core tools/inlay/inlay_modules.c \
    tools/inlay/inlay_host.c \
    -o build/inlay/portable/inlay_host

c++ -x c++ -std=c++11 -pedantic -Wall -Wextra -Werror \
    $core tools/inlay/inlay_modules.c \
    tools/inlay/inlay_host.c \
    -o build/inlay/portable/inlay_host_cpp11

if command -v cc65 >/dev/null 2>&1 &&
   command -v ca65 >/dev/null 2>&1; then
    for unit in $core; do
        name=$(basename "$unit" .c)
        cc65 -t none -I tools/inlay -o "build/inlay/cc65/$name.s" "$unit"
        ca65 -t none -o "build/inlay/cc65/$name.o" "build/inlay/cc65/$name.s"
    done
    cc65 -t none -I tools/inlay \
        -o build/inlay/cc65/inlay_modules.s tools/inlay/inlay_modules.c
    ca65 -t none -o build/inlay/cc65/inlay_modules.o \
        build/inlay/cc65/inlay_modules.s
    echo "Inlay portability: strict C89/C99/C++11, UBSan, and cc65 passed"
else
    echo "Inlay portability: strict C89/C99/C++11 and UBSan passed; cc65 unavailable"
fi
