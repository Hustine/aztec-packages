#!/bin/bash
set -eu

# Get the name of the script without the path and extension
SCRIPT_NAME=$(basename "$0" .sh)

# Redirect stdout and stderr to <script_name>.log while also printing to the console
exec > >(tee -a "$(dirname $0)/logs/${SCRIPT_NAME}.log") 2> >(tee -a "$(dirname $0)/logs/${SCRIPT_NAME}.log" >&2)

# Starts the Boot Node

# Set environment variables
export PORT="8080"
export LOG_LEVEL="debug"
export DEBUG="aztec:*,-aztec:avm_simulator:*"
export ETHEREUM_HOST="http://127.0.0.1:8545"
export P2P_ENABLED="true"
export VALIDATOR_DISABLED="true"
export SEQ_MAX_SECONDS_BETWEEN_BLOCKS="0"
export SEQ_MIN_TX_PER_BLOCK="1"
export P2P_TCP_ANNOUNCE_ADDR="127.0.0.1:40400"
export P2P_UDP_ANNOUNCE_ADDR="127.0.0.1:40400"
export P2P_TCP_LISTEN_ADDR="0.0.0.0:40400"
export P2P_UDP_LISTEN_ADDR="0.0.0.0:40400"
export VALIDATOR_PRIVATE_KEY="0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a"
REPO=$(git rev-parse --show-toplevel)

echo "Waiting for l1 contracts to be deployed..."
until [ -f "$REPO"/yarn-project/end-to-end/scripts/native-network/l1-contracts.env ] ; do
  sleep 1
done
echo "Done waiting."

source "$REPO"/yarn-project/end-to-end/scripts/native-network/l1-contracts.env

function filter_noise() {
  grep -Ev "node_getProvenBlockNumber|getBlocks|Last block mined|Running random nodes query|Not creating block because not enough txs in the pool|Peers to connect"
}

# Start the Aztec node with the sequencer and archiver
node --no-warnings "$REPO"/yarn-project/aztec/dest/bin/index.js start --node --archiver --sequencer --pxe 2>&1 | filter_noise