#!/usr/bin/env bash

#####################################################
# ArchiSteamFarm installer made by Floofie. #
#####################################################

# -e option instructs bash to immediately exit if any command [1] has a non-zero exit status
set -e

####### VARIABLES ########

# TODO: this
## Give settings their default values. These can be changed by prompts later in the script.
#NEW_USER=true # Root is required for this
#STARTUP=true  # Root is required for this
#IPC=true

# Colors
COL_LIGHT_GREEN='\e[1;32m'
COL_LIGHT_RED='\e[1;31m'
COL_LIGHT_BLUE='\e[1;34m'
COL_NC='\e[0m' # No Color

TICK="[${COL_LIGHT_GREEN}✓${COL_NC}]"
CROSS="[${COL_LIGHT_RED}✗${COL_NC}]"
INFO="[${COL_LIGHT_BLUE}i${COL_NC}]"

# Message Formatting
ok_message() { 
    formatted_message "${TICK}" "$@"
}

error_message() { 
    >&2 formatted_message "${CROSS}" "$@"
}

info_message() { 
    formatted_message "${INFO}" "$@"
}

formatted_message() { 
    SIGN="$1"; shift

    printf "%s | %s" "${SIGN}" "$1"; shift
    echo

    LINES_ARRAY=("$@")

    for line in "${LINES_ARRAY[@]}"; do
        printf "    | %s" "${line}"
        echo
    done
}


####### SCRIPT ########

# Simple little thing to make sure that we have the packages available
dep_check() {
    if ! command -v "$@" > /dev/null ; then
        error_message "You don't have $* installed!" \
            "Please install it before continuing." &&
        exit 1
    fi
}
dep_check wget 
dep_check openssl 
dep_check unzip

main() {
    # Check for root
    local str="Root user check"
    
    # If the user ID is zero (root),
    if [[ "${EUID}" -eq 0 ]]; then
        # all is cool
        ok_message "${str}"
        echo

        os_check
        arch_check
        useradd -m asf # Add ASF user
        download
        crypt
        config
        tidy_up
    else # Not ran as root
        error_message "${str}" \
            "This ASF script requires elevated privileges to run." \
            "For any concerns with running as root, you can check the installer." \
            "Make sure you downloaded this from a trusted source!" 
        exit 1
    fi
}

os_check() {
    info_message "Checking OS..."

    # Check if running GNU/Linux type OS
    case $OSTYPE in linux-gnu*)
        # Check if they are using systemd init
        if [[ -d '/run/systemd/system' ]]; then
            ok_message "OS supported!"
            echo
        else
            error_message "You're using OpenRC or some other init system I don't know."\
            "If you know how to send a pull request for this, please do!"
            exit 1
        fi
        ;;
    *)
    
        error_message "OS type not found. If you're running GNU/Linux, please report this on GitHub!"
        exit 1
    esac
}

arch_check() {
    info_message "Checking architecture..."
    case $(uname -m) in
        x86_64)
            ARCH=x64
            ;;
        arm|armv7l)
            ARCH=arm
            ;;
        aarch64)
            ARCH=arm64
            ;;
        *)
        error_message "Architecture type not found. You will probably have to run the generic version of ASF, which is out of this scripts capabilities." \
            "If you believe this is an error, please report this on GitHub!"
        exit 1
        ;;
    esac

    ok_message "Architecture identified as $(uname -m), so we will download the $ARCH version."
    echo
    ASF=https://github.com/JustArchiNET/ArchiSteamFarm/releases/latest/download/ASF-linux-$ARCH.zip
}

download() {
    info_message "Downloading..."
    wget $ASF -O /tmp/ASF.zip
    ok_message "Download complete!"

    # Unzip it
    mkdir /home/asf/ArchiSteamFarm
    unzip -qq /tmp/ASF.zip -d /home/asf/ArchiSteamFarm
    ok_message "Extracted to directory"
    echo
}

crypt() {
    info_message "Setting custom Cryptkey in /etc/asf"
    mkdir -p /etc/asf
    
    #Make sure no one else can touch it
    chown -hR root:root /etc/asf
    chmod 700 /etc/asf
    
    # The actual Cryptkey file
    touch /etc/asf/asf
    echo ASF_CRYPTKEY="$(openssl rand -hex 64)" >> /etc/asf/asf
    ok_message "Custom Cryptkey set!"
    echo
}

config() {
    # Add config for IPC
    cat > /home/asf/ArchiSteamFarm/config/IPC.config <<EOF
    {
        "Kestrel": {
            "Endpoints": {
    		    "HTTP4": {
    			    "Url": "http://0.0.0.0:1242"
    			}
            }
        },
        "KnownNetworks": [
            "10.0.0.0/8",
            "172.16.0.0/12",
            "192.168.0.0/16"
        ]
    }
EOF
    
    # Get a password. TODO: MAKE THIS MORE SECURE OR ASK USER FOR A PASSWORD!!
    PW=$(head /dev/urandom | sha256sum | base64 | head -c 32 ; echo)
    
    # Specify the password and headless mode
    cat > /home/asf/ArchiSteamFarm/config/ASF.json <<EOF
    {
      "Headless": true,
      "IPCPassword": "$PW"
    }
EOF
}

tidy_up () {
    info_message "Tidying up..."
    # Double check the permissions
    chown -R asf:asf /home/asf/ArchiSteamFarm
    chmod -R 700 /home/asf

    # Get the system file and enable it immediately
    ln -s /home/asf/ArchiSteamFarm/ArchiSteamFarm\@.service /etc/systemd/system/.
    systemctl enable --quiet --now ArchiSteamFarm@asf.service

    # Lock down the account
    passwd -l asf > /dev/null
    usermod --shell /usr/sbin/nologin asf
    # Delete tmp file
    rm /tmp/ASF.zip
}

main

# Echo PW and plead user to change it 
ok_message "The ASF install is complete!" \
    "To access the IPC, go to http://localhost:1242 on this machine and use the password $(tput bold)$PW$(tput sgr0)"\
    "Please make sure to change the IPC password as soon as possible!"