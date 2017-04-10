#!/usr/bin/env bash

# Checks to make sure liberasurecode is working before starting SAIO

set -eo pipefail

progress() {
    local pid=${1}
    while ps -ef | grep $pid >/dev/null 2>&1; do
        echo -n "."
        sleep .5
    done
}

cd ${LIBERASURECODE_DIR} || { echo "ERROR: ${LIBERASURECODE_DIR} not found"; exit 1; }

echo "Checking liberasurecode..."
sleep 3
if ! make test; then
    echo ""
    echo "liberasurecode test failed... reconfiguring liberasurecode."
    echo ""
    echo -n "Preparing for build."
    sudo make clean >/dev/null 2>&1 || { echo "ERROR: failed to clean liberasurecode"; exit 1; }
    progress ${!}
    sudo ./autogen.sh >/dev/null 2>&1 || { echo "ERROR: failed to generate configuration fiile"; exit 1; } &
    progress ${!}
    sudo ./configure >/dev/null 2>&1 || { echo "ERROR: failed to configure liberasurecode"; exit 1; }
    progress ${!}
    echo "ready"
    echo ""
    echo -n "Compiling liberasurecode."
    sudo make >/dev/null 2>&1 || { echo "ERROR: failed to clean liberasurecode"; exit 1; } &
    progress ${!}
    echo "done"
    echo ""
    echo "Testing liberasurecode..."
    echo ""
    sleep 3
    sudo make test || { echo "ERROR: liberasurecode tests failed"; exit 1; }
    echo ""
    echo "liberasurecode tests passed"
    echo ""
    echo -n "Installing liberasurecode."
    sudo make install >/dev/null 2>&1 || { echo "ERROR: failed to install liberasurecode"; exit 1; } &
    progress ${!}
    echo "done"
    sudo ldconfig
    echo "liberasurecode reconfiguration complete."
else
    echo ""
    echo "liberasurecode: ok"
fi
cd -
exit 0
