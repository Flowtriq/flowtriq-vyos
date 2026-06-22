#!/bin/sh
# Flowtriq VyOS Command Generator
# Generates VyOS configuration commands for NetFlow/sFlow export to ftagent.
#
# Usage:
#   sh vyos-commands.sh
#
# This script outputs the exact VyOS CLI commands to configure flow export.
# Copy and paste the output into your VyOS router's configure mode.
#
# License: MIT

set -e

# -- Colors ---------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo "${BLUE}Flowtriq VyOS Command Generator${NC}"
echo ""

# -- Collect inputs -------------------------------------------------------

printf "${YELLOW}ftagent host IP address:${NC} "
read FTAGENT_HOST
if [ -z "$FTAGENT_HOST" ]; then
    echo "${RED}Error: ftagent host IP is required${NC}"
    exit 1
fi

printf "${YELLOW}WAN interface [eth0]:${NC} "
read WAN_IF
WAN_IF=${WAN_IF:-eth0}

echo ""
echo "${BLUE}Flow protocol:${NC}"
echo "  ${CYAN}1)${NC} NetFlow v9 (recommended)"
echo "  ${CYAN}2)${NC} NetFlow v5"
echo "  ${CYAN}3)${NC} sFlow"
printf "${YELLOW}Select [1]:${NC} "
read PROTO_INPUT
PROTO_INPUT=${PROTO_INPUT:-1}

case "$PROTO_INPUT" in
    1) FLOW_PROTO="netflow"; FLOW_VERSION="9"; DEFAULT_PORT="2055" ;;
    2) FLOW_PROTO="netflow"; FLOW_VERSION="5"; DEFAULT_PORT="2055" ;;
    3) FLOW_PROTO="sflow"; FLOW_VERSION=""; DEFAULT_PORT="6343" ;;
    *) echo "${RED}Invalid selection${NC}"; exit 1 ;;
esac

printf "${YELLOW}Export port [${DEFAULT_PORT}]:${NC} "
read FLOW_PORT
FLOW_PORT=${FLOW_PORT:-$DEFAULT_PORT}

# -- Generate commands ----------------------------------------------------

echo ""
echo "${GREEN}============================================================${NC}"
echo "${GREEN}VyOS Configuration Commands${NC}"
echo "${GREEN}============================================================${NC}"
echo ""
echo "Enter VyOS configure mode first:"
echo ""
echo "  ${CYAN}configure${NC}"
echo ""

if [ "$FLOW_PROTO" = "netflow" ]; then
    echo "Then run:"
    echo ""
    echo "  ${CYAN}set system flow-accounting interface ${WAN_IF}${NC}"
    echo "  ${CYAN}set system flow-accounting netflow version ${FLOW_VERSION}${NC}"
    echo "  ${CYAN}set system flow-accounting netflow server ${FTAGENT_HOST} port ${FLOW_PORT}${NC}"
    echo "  ${CYAN}set system flow-accounting netflow timeout expiry-interval 60${NC}"
    echo "  ${CYAN}commit${NC}"
    echo "  ${CYAN}save${NC}"
    echo ""
    echo "${GREEN}------------------------------------------------------------${NC}"
    echo ""
    echo "Plain text (copy-paste friendly):"
    echo ""
    echo "configure"
    echo "set system flow-accounting interface ${WAN_IF}"
    echo "set system flow-accounting netflow version ${FLOW_VERSION}"
    echo "set system flow-accounting netflow server ${FTAGENT_HOST} port ${FLOW_PORT}"
    echo "set system flow-accounting netflow timeout expiry-interval 60"
    echo "commit"
    echo "save"
elif [ "$FLOW_PROTO" = "sflow" ]; then
    echo "Then run:"
    echo ""
    echo "  ${CYAN}set system flow-accounting interface ${WAN_IF}${NC}"
    echo "  ${CYAN}set system flow-accounting sflow server ${FTAGENT_HOST} port ${FLOW_PORT}${NC}"
    echo "  ${CYAN}commit${NC}"
    echo "  ${CYAN}save${NC}"
    echo ""
    echo "${GREEN}------------------------------------------------------------${NC}"
    echo ""
    echo "Plain text (copy-paste friendly):"
    echo ""
    echo "configure"
    echo "set system flow-accounting interface ${WAN_IF}"
    echo "set system flow-accounting sflow server ${FTAGENT_HOST} port ${FLOW_PORT}"
    echo "commit"
    echo "save"
fi

echo ""
echo "${GREEN}------------------------------------------------------------${NC}"
echo ""
echo "Verify after applying:"
echo ""
echo "  ${CYAN}show flow-accounting${NC}"
echo ""

# -- To remove later ------------------------------------------------------
echo "${YELLOW}To remove flow export later:${NC}"
echo ""
if [ "$FLOW_PROTO" = "netflow" ]; then
    echo "  configure"
    echo "  delete system flow-accounting netflow server ${FTAGENT_HOST}"
    echo "  delete system flow-accounting interface ${WAN_IF}"
    echo "  commit"
    echo "  save"
elif [ "$FLOW_PROTO" = "sflow" ]; then
    echo "  configure"
    echo "  delete system flow-accounting sflow server ${FTAGENT_HOST}"
    echo "  delete system flow-accounting interface ${WAN_IF}"
    echo "  commit"
    echo "  save"
fi
echo ""
