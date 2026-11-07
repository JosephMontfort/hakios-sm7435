#!/bin/bash
# Apply Garnet platform onto HakiOS's UEFI (Mu-Silicium)
exec "$(dirname "$(readlink -f "$0")")/../../../uefi/apply.sh" garnet
