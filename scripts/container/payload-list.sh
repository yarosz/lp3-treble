# shellcheck shell=sh
# Sourced by both patch-gsi.sh (host, bash) and container/patch.sh (Alpine, sh), so the host and
# the container count the payload with the identical expression. Do not run it.
# macOS junk (.DS_Store, AppleDouble ._*) is excluded everywhere.

payload_junk() { # payload_junk <dir>: junk entries, relative
  (cd "$1" && find . \( -name .DS_Store -o -name '._*' \) -print | sed 's|^\./||' | LC_ALL=C sort)
}
payload_special() { # payload_special <dir>: anything that is not a directory or regular file
  (cd "$1" && find . \( -name .DS_Store -o -name '._*' \) -prune -o ! -type d ! -type f -print | sed 's|^\./||' | LC_ALL=C sort)
}
payload_files() { # payload_files <dir>: files to inject, as /abs/in/image paths
  (cd "$1" && find . \( -name .DS_Store -o -name '._*' \) -prune -o -type f ! -path ./build.prop.append ! -path ./contexts.txt -print | sed 's|^\.||' | LC_ALL=C sort)
}
