#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Resources
fetch() {
    local name="$1" hash="$2" url="$3"
    if [[ ! -f "Resources/$name" ]]; then
        local staging
        staging=$(mktemp "${TMPDIR:-/tmp}/am-artwork.XXXXXX")
        curl --fail --location --proto '=https' --proto-redir '=https' "$url" -o "$staging"
        printf '%s  %s\n' "$hash" "$staging" | shasum -a 256 -c -
        cp "$staging" "Resources/$name"
    fi
    printf '%s  %s\n' "$hash" "Resources/$name" | shasum -a 256 -c -
}
fetch am-infinity.png 1a1c41f5ed8290526cae2951972713982e63382a97bc1d7a4cf8d1dc733e680f 'https://ammaster.angrymiao.com/mouse/assets/device_am35_m_a-1a1c41f5.png'
fetch am-infinity-black.png 90679245da81bab3db731f450e7aa58a4c841542c8e194c707d261d84ba242f9 'https://ammaster.angrymiao.com/mouse/assets/device_am35_m_b-90679245.png'
