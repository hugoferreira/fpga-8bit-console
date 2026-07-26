#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$root"

mkdir -p build/laasm/portable build/laasm/cc65

forbidden='malloc|calloc|realloc|free|fopen|fclose|popen|pclose|system|getenv|setlocale|json'
if grep -En "$forbidden" tools/laasm/laasm_core.c \
    tools/laasm/laasm_modules.c tools/laasm/laasm.h; then
    echo "laasm portability: forbidden host dependency in semantic core" >&2
    exit 1
fi

cc -std=c89 -pedantic -Wall -Wextra -Werror \
    -c tools/laasm/laasm_core.c -o build/laasm/portable/laasm_core.o
cc -std=c89 -pedantic -Wall -Wextra -Werror \
    -c tools/laasm/laasm_modules.c -o build/laasm/portable/laasm_modules.o

cc -std=c89 -pedantic -Wall -Wextra -Werror \
    -fsanitize=undefined -fno-omit-frame-pointer \
    tools/laasm/laasm_core.c tools/laasm/test_laasm.c \
    -o build/laasm/portable/test_laasm_ubsan
build/laasm/portable/test_laasm_ubsan

cc -std=c89 -pedantic -Wall -Wextra -Werror \
    -fsanitize=undefined -fno-omit-frame-pointer \
    tools/laasm/laasm_core.c tools/laasm/laasm_modules.c \
    tools/laasm/test_modules.c \
    -o build/laasm/portable/test_modules_ubsan
build/laasm/portable/test_modules_ubsan

cc -std=c99 -pedantic -Wall -Wextra -Werror \
    tools/laasm/laasm_core.c tools/laasm/laasm_modules.c \
    tools/laasm/laasm_host.c \
    -o build/laasm/portable/laasm_host

if command -v cc65 >/dev/null 2>&1 &&
   command -v ca65 >/dev/null 2>&1; then
    cc65 -t none -I tools/laasm \
        -o build/laasm/cc65/laasm_core.s tools/laasm/laasm_core.c
    ca65 -t none -o build/laasm/cc65/laasm_core.o \
        build/laasm/cc65/laasm_core.s
    cc65 -t none -I tools/laasm \
        -o build/laasm/cc65/laasm_modules.s tools/laasm/laasm_modules.c
    ca65 -t none -o build/laasm/cc65/laasm_modules.o \
        build/laasm/cc65/laasm_modules.s
    echo "laasm portability: strict C89, UBSan, and cc65 smoke build passed"
else
    echo "laasm portability: strict C89 and UBSan passed; cc65 unavailable"
fi
