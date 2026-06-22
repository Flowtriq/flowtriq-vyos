#!/bin/sh
# Flowtriq VyOS Integration Setup
# Two integration modes: direct ftagent install or NetFlow/sFlow export
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Flowtriq/flowtriq-vyos/main/setup.sh | sh
#
# Or clone and run:
#   git clone https://github.com/Flowtriq/flowtriq-vyos.git
#   cd flowtriq-vyos
#   sh setup.sh
#
# Supports: VyOS 1.4+ (rolling), VyOS 1.3.x (LTS)
# License: MIT

set -e

# -- Colors ---------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# -- Banner ---------------------------------------------------------------
echo ""
echo "${CYAN}  ______ _               _        _        ${NC}"
echo "${CYAN} |  ____| |             | |      (_)       ${NC}"
echo "${CYAN} | |__  | | _____      _| |_ _ __ _  __ _ ${NC}"
echo "${CYAN} |  __| | |/ _ \ \ /\ / / __| '__| |/ _ \\${NC}"
echo "${CYAN} | |    | | (_) \ V  V /| |_| |  | | (_) |${NC}"
echo "${CYAN} |_|    |_|\___/ \_/\_/  \__|_|  |_|\__, |${NC}"
echo "${CYAN}                                        | |${NC}"
echo "${CYAN}                VyOS Setup              |_|${NC}"
echo ""
echo "${BLUE}DDoS detection for VyOS routers${NC}"
echo ""

# -- Detect environment ---------------------------------------------------
IS_VYOS=false
if [ -d /etc/vyos ] || [ -f /etc/vyos/config.boot.default ]; then
    IS_VYOS=true
    echo "${GREEN}Detected: Running on VyOS${NC}"
    VYOS_VERSION=$(cat /etc/vyos/version 2>/dev/null || echo "unknown")
    echo "${GREEN}VyOS version: ${VYOS_VERSION}${NC}"
elif [ -f /etc/debian_version ]; then
    echo "${GREEN}Detected: Debian-based Linux (not VyOS)${NC}"
else
    echo "${GREEN}Detected: $(uname -s)${NC}"
fi
echo ""

# -- Choose integration mode ----------------------------------------------
echo "${BLUE}Choose integration mode:${NC}"
echo ""
echo "  ${CYAN}1)${NC} Direct install (recommended)"
echo "     Install ftagent directly on this VyOS box."
echo "     Sub-second detection, PCAP evidence, full capabilities."
echo ""
echo "  ${CYAN}2)${NC} NetFlow/sFlow export"
echo "     Export flows from VyOS to a remote ftagent host."
echo "     Minimal CPU on VyOS, requires a separate Linux host."
echo ""

if [ "$IS_VYOS" = true ]; then
    printf "${YELLOW}Select mode [1]:${NC} "
else
    echo "${YELLOW}Note: You are not running on VyOS.${NC}"
    echo "  Mode 1 will install ftagent on this host."
    echo "  Mode 2 will generate VyOS commands to run on your router."
    echo ""
    printf "${YELLOW}Select mode [2]:${NC} "
fi

read MODE_INPUT

if [ "$IS_VYOS" = true ]; then
    MODE=${MODE_INPUT:-1}
else
    MODE=${MODE_INPUT:-2}
fi

# =========================================================================
# Mode 1: Direct install
# =========================================================================
if [ "$MODE" = "1" ]; then
    echo ""
    echo "${GREEN}Mode 1: Direct ftagent install${NC}"
    echo ""

    # Check Python
    if ! command -v python3 >/dev/null 2>&1; then
        echo "${RED}Error: Python 3 is required but not found.${NC}"
        echo "On VyOS, Python 3 should be available by default."
        echo "If not, check your VyOS version (1.4+ recommended)."
        exit 1
    fi

    PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
    echo "${GREEN}Python version: ${PYTHON_VERSION}${NC}"

    # Check pip
    if ! command -v pip3 >/dev/null 2>&1; then
        echo "${YELLOW}pip3 not found. Installing...${NC}"
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get update -qq && sudo apt-get install -y -qq python3-pip
        else
            echo "${RED}Cannot install pip3 automatically. Install it manually and re-run.${NC}"
            exit 1
        fi
    fi

    # Collect Flowtriq API key
    printf "${YELLOW}Enter your Flowtriq API key:${NC} "
    read API_KEY
    if [ -z "$API_KEY" ]; then
        echo "${RED}Error: API key is required. Get one at https://flowtriq.com/signup${NC}"
        exit 1
    fi

    # Detect WAN interface
    WAN_IF=""
    if [ "$IS_VYOS" = true ]; then
        WAN_IF=$(ip route show default 2>/dev/null | awk '{print $5}' | head -1 || true)
    else
        WAN_IF=$(ip route show default 2>/dev/null | awk '{print $5}' | head -1 || true)
    fi

    if [ -n "$WAN_IF" ]; then
        printf "${YELLOW}Monitor interface [${WAN_IF}]:${NC} "
        read USER_IF
        WAN_IF=${USER_IF:-$WAN_IF}
    else
        printf "${YELLOW}Monitor interface (e.g. eth0):${NC} "
        read WAN_IF
    fi

    if [ -z "$WAN_IF" ]; then
        echo "${RED}Error: Interface is required${NC}"
        exit 1
    fi

    # Summary
    echo ""
    echo "${BLUE}Configuration summary:${NC}"
    echo "  Mode:            Direct install"
    echo "  Interface:       $WAN_IF"
    echo "  API key:         ${API_KEY%${API_KEY#????}}..."
    echo ""
    printf "${YELLOW}Proceed? [Y/n]:${NC} "
    read CONFIRM
    case "$CONFIRM" in
        [nN]*) echo "Aborted."; exit 0 ;;
    esac

    # Install ftagent
    echo ""
    echo "${GREEN}Installing ftagent...${NC}"
    pip3 install ftagent

    # Create config directory
    sudo mkdir -p /etc/ftagent

    # Write config
    CONFIG_FILE="/etc/ftagent/config.json"
    sudo python3 -c "
import json, os
cfg = {}
if os.path.exists('$CONFIG_FILE'):
    with open('$CONFIG_FILE') as f:
        cfg = json.load(f)
cfg['api_key'] = '$API_KEY'
cfg['interface'] = '$WAN_IF'
with open('$CONFIG_FILE', 'w') as f:
    json.dump(cfg, f, indent=2)
print('Wrote config to $CONFIG_FILE')
"

    # Create systemd service
    UNIT_FILE="/etc/systemd/system/ftagent.service"
    if [ ! -f "$UNIT_FILE" ]; then
        echo "${GREEN}Creating systemd service...${NC}"
        sudo tee "$UNIT_FILE" > /dev/null <<'UNIT'
[Unit]
Description=Flowtriq Agent - DDoS Detection
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/ftagent
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNIT
    fi

    # Enable and start
    sudo systemctl daemon-reload
    sudo systemctl enable ftagent
    sudo systemctl restart ftagent

    echo ""
    echo "${GREEN}ftagent installed and running.${NC}"
    echo ""
    echo "${GREEN}Verify it's working:${NC}"
    echo "  ${CYAN}sudo systemctl status ftagent${NC}"
    echo "  ${CYAN}sudo journalctl -u ftagent -f${NC}"

# =========================================================================
# Mode 2: NetFlow/sFlow export
# =========================================================================
elif [ "$MODE" = "2" ]; then
    echo ""
    echo "${GREEN}Mode 2: NetFlow/sFlow export${NC}"
    echo ""

    # Flow protocol
    echo "${BLUE}Select flow protocol:${NC}"
    echo "  ${CYAN}1)${NC} NetFlow v9 (recommended)"
    echo "  ${CYAN}2)${NC} NetFlow v5"
    echo "  ${CYAN}3)${NC} sFlow"
    echo ""
    printf "${YELLOW}Select protocol [1]:${NC} "
    read PROTO_INPUT
    PROTO_INPUT=${PROTO_INPUT:-1}

    case "$PROTO_INPUT" in
        1) FLOW_PROTO="netflow"; FLOW_VERSION="9"; FLOW_PORT="2055" ;;
        2) FLOW_PROTO="netflow"; FLOW_VERSION="5"; FLOW_PORT="2055" ;;
        3) FLOW_PROTO="sflow"; FLOW_VERSION=""; FLOW_PORT="6343" ;;
        *) echo "${RED}Invalid selection${NC}"; exit 1 ;;
    esac

    # Collect target info
    printf "${YELLOW}IP address of your ftagent host:${NC} "
    read FTAGENT_HOST
    if [ -z "$FTAGENT_HOST" ]; then
        echo "${RED}Error: ftagent host IP is required${NC}"
        exit 1
    fi

    printf "${YELLOW}Export port [${FLOW_PORT}]:${NC} "
    read USER_PORT
    FLOW_PORT=${USER_PORT:-$FLOW_PORT}

    # Detect WAN interface
    WAN_IF=""
    if [ "$IS_VYOS" = true ]; then
        WAN_IF=$(ip route show default 2>/dev/null | awk '{print $5}' | head -1 || true)
    fi

    if [ -n "$WAN_IF" ]; then
        printf "${YELLOW}WAN interface [${WAN_IF}]:${NC} "
        read USER_IF
        WAN_IF=${USER_IF:-$WAN_IF}
    else
        printf "${YELLOW}WAN interface (e.g. eth0):${NC} "
        read WAN_IF
    fi

    if [ -z "$WAN_IF" ]; then
        echo "${RED}Error: WAN interface is required${NC}"
        exit 1
    fi

    # Summary
    echo ""
    echo "${BLUE}Configuration summary:${NC}"
    echo "  Mode:            NetFlow/sFlow export"
    echo "  Protocol:        ${FLOW_PROTO} ${FLOW_VERSION}"
    echo "  Interface:       $WAN_IF"
    echo "  ftagent host:    $FTAGENT_HOST:$FLOW_PORT"
    echo ""
    printf "${YELLOW}Proceed? [Y/n]:${NC} "
    read CONFIRM
    case "$CONFIRM" in
        [nN]*) echo "Aborted."; exit 0 ;;
    esac

    echo ""

    # Apply config directly on VyOS or print commands
    if [ "$IS_VYOS" = true ]; then
        echo "${GREEN}Applying VyOS configuration...${NC}"
        echo ""

        if [ "$FLOW_PROTO" = "netflow" ]; then
            # Apply via vbash
            /bin/vbash -c "
source /opt/vyatta/etc/functions/script-begin
set system flow-accounting interface $WAN_IF
set system flow-accounting netflow version $FLOW_VERSION
set system flow-accounting netflow server $FTAGENT_HOST port $FLOW_PORT
set system flow-accounting netflow timeout expiry-interval 60
commit
save
source /opt/vyatta/etc/functions/script-end
" 2>/dev/null && {
                echo "${GREEN}VyOS NetFlow configuration applied and saved.${NC}"
            } || {
                echo "${YELLOW}Could not apply automatically. Run these commands in VyOS configure mode:${NC}"
                echo ""
                echo "  ${CYAN}configure${NC}"
                echo "  ${CYAN}set system flow-accounting interface ${WAN_IF}${NC}"
                echo "  ${CYAN}set system flow-accounting netflow version ${FLOW_VERSION}${NC}"
                echo "  ${CYAN}set system flow-accounting netflow server ${FTAGENT_HOST} port ${FLOW_PORT}${NC}"
                echo "  ${CYAN}set system flow-accounting netflow timeout expiry-interval 60${NC}"
                echo "  ${CYAN}commit${NC}"
                echo "  ${CYAN}save${NC}"
            }
        elif [ "$FLOW_PROTO" = "sflow" ]; then
            /bin/vbash -c "
source /opt/vyatta/etc/functions/script-begin
set system flow-accounting interface $WAN_IF
set system flow-accounting sflow server $FTAGENT_HOST port $FLOW_PORT
commit
save
source /opt/vyatta/etc/functions/script-end
" 2>/dev/null && {
                echo "${GREEN}VyOS sFlow configuration applied and saved.${NC}"
            } || {
                echo "${YELLOW}Could not apply automatically. Run these commands in VyOS configure mode:${NC}"
                echo ""
                echo "  ${CYAN}configure${NC}"
                echo "  ${CYAN}set system flow-accounting interface ${WAN_IF}${NC}"
                echo "  ${CYAN}set system flow-accounting sflow server ${FTAGENT_HOST} port ${FLOW_PORT}${NC}"
                echo "  ${CYAN}commit${NC}"
                echo "  ${CYAN}save${NC}"
            }
        fi
    else
        echo "${BLUE}VyOS configuration commands:${NC}"
        echo ""
        echo "SSH into your VyOS router and run these commands:"
        echo ""
        echo "  ${CYAN}configure${NC}"

        if [ "$FLOW_PROTO" = "netflow" ]; then
            echo "  ${CYAN}set system flow-accounting interface ${WAN_IF}${NC}"
            echo "  ${CYAN}set system flow-accounting netflow version ${FLOW_VERSION}${NC}"
            echo "  ${CYAN}set system flow-accounting netflow server ${FTAGENT_HOST} port ${FLOW_PORT}${NC}"
            echo "  ${CYAN}set system flow-accounting netflow timeout expiry-interval 60${NC}"
            echo "  ${CYAN}commit${NC}"
            echo "  ${CYAN}save${NC}"
        elif [ "$FLOW_PROTO" = "sflow" ]; then
            echo "  ${CYAN}set system flow-accounting interface ${WAN_IF}${NC}"
            echo "  ${CYAN}set system flow-accounting sflow server ${FTAGENT_HOST} port ${FLOW_PORT}${NC}"
            echo "  ${CYAN}commit${NC}"
            echo "  ${CYAN}save${NC}"
        fi
    fi

    # ftagent config
    echo ""
    echo "${BLUE}-----------------------------------------------------------${NC}"
    echo ""
    echo "${GREEN}Next: Configure ftagent on your Linux host (${FTAGENT_HOST})${NC}"
    echo ""
    echo "Add this to your ftagent config (/etc/ftagent/config.json):"
    echo ""
    if [ "$FLOW_PROTO" = "netflow" ]; then
        echo "${CYAN}  \"flow_enabled\": true,${NC}"
        echo "${CYAN}  \"flow_protocol\": \"netflow_v${FLOW_VERSION}\",${NC}"
        echo "${CYAN}  \"flow_port\": ${FLOW_PORT},${NC}"
        echo "${CYAN}  \"flow_node_ip\": \"YOUR_VYOS_WAN_IP\"${NC}"
    elif [ "$FLOW_PROTO" = "sflow" ]; then
        echo "${CYAN}  \"flow_enabled\": true,${NC}"
        echo "${CYAN}  \"flow_protocol\": \"sflow_v5\",${NC}"
        echo "${CYAN}  \"flow_port\": ${FLOW_PORT},${NC}"
        echo "${CYAN}  \"flow_node_ip\": \"YOUR_VYOS_WAN_IP\"${NC}"
    fi
    echo ""
    echo "Then restart ftagent:"
    echo "  ${CYAN}sudo systemctl restart ftagent${NC}"

else
    echo "${RED}Invalid selection. Choose 1 or 2.${NC}"
    exit 1
fi

# -- Verification ---------------------------------------------------------
echo ""
echo "${BLUE}-----------------------------------------------------------${NC}"
echo ""
echo "${GREEN}Verification:${NC}"
echo ""
if [ "$MODE" = "1" ]; then
    echo "  ${CYAN}sudo systemctl status ftagent${NC}"
    echo "  ${CYAN}sudo journalctl -u ftagent -f${NC}"
else
    if [ "$IS_VYOS" = true ]; then
        echo "  On VyOS, verify flow-accounting is active:"
        echo "  ${CYAN}show flow-accounting${NC}"
        echo ""
    fi
    echo "  On your ftagent host, verify flows are arriving:"
    echo "  ${CYAN}sudo journalctl -u ftagent -f | grep flow${NC}"
fi
echo ""
echo "${BLUE}Dashboard:${NC} https://flowtriq.com/dashboard"
echo "${BLUE}Docs:${NC}      https://flowtriq.com/docs"
echo "${BLUE}Support:${NC}   https://discord.gg/SsTWMYuyGG"
echo ""
echo "${GREEN}Setup complete.${NC}"
