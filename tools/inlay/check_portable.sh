#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$root"

mkdir -p build/inlay/portable build/inlay/cc65

forbidden='malloc|calloc|realloc|free|fopen|fclose|popen|pclose|system|getenv|setlocale|json'
if grep -En "$forbidden" tools/inlay/inlay_core.c \
    tools/inlay/inlay_modules.c tools/inlay/inlay.h; then
    echo "Inlay portability: forbidden host dependency in semantic core" >&2
    exit 1
fi

cc -std=c89 -pedantic -Wall -Wextra -Werror \
    -c tools/inlay/inlay_core.c -o build/inlay/portable/inlay_core.o
cc -std=c89 -pedantic -Wall -Wextra -Werror \
    -c tools/inlay/inlay_modules.c -o build/inlay/portable/inlay_modules.o

cc -std=c89 -pedantic -Wall -Wextra -Werror \
    -fsanitize=undefined -fno-omit-frame-pointer \
    tools/inlay/inlay_core.c tools/inlay/test_inlay.c \
    -o build/inlay/portable/test_inlay_ubsan
build/inlay/portable/test_inlay_ubsan

cc -std=c89 -pedantic -Wall -Wextra -Werror \
    -fsanitize=undefined -fno-omit-frame-pointer \
    tools/inlay/inlay_core.c tools/inlay/inlay_modules.c \
    tools/inlay/test_modules.c \
    -o build/inlay/portable/test_modules_ubsan
build/inlay/portable/test_modules_ubsan

cc -std=c99 -pedantic -Wall -Wextra -Werror \
    tools/inlay/inlay_core.c tools/inlay/inlay_modules.c \
    tools/inlay/inlay_host.c \
    -o build/inlay/portable/inlay_host

c++ -x c++ -std=c++11 -pedantic -Wall -Wextra -Werror \
    tools/inlay/inlay_core.c tools/inlay/inlay_modules.c \
    tools/inlay/inlay_host.c \
    -o build/inlay/portable/inlay_host_cpp11

if command -v cc65 >/dev/null 2>&1 &&
   command -v ca65 >/dev/null 2>&1; then
    cc65 -t none -I tools/inlay \
        -o build/inlay/cc65/inlay_core.s tools/inlay/inlay_core.c
    ca65 -t none -o build/inlay/cc65/inlay_core.o \
        build/inlay/cc65/inlay_core.s
    cc65 -t none -I tools/inlay \
        -o build/inlay/cc65/inlay_modules.s tools/inlay/inlay_modules.c
    ca65 -t none -o build/inlay/cc65/inlay_modules.o \
        build/inlay/cc65/inlay_modules.s
    echo "Inlay portability: strict C89/C99/C++11, UBSan, and cc65 passed"
else
    echo "Inlay portability: strict C89/C99/C++11 and UBSan passed; cc65 unavailable"
fi
