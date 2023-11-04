#!/bin/bash
set -e

MLD_MANAGE_PACKAGES_SCRIPT_PATH="bin/manage_packages.sh"

#
# !! DO NOT UPDATE THE SCRIPT BELOW THIS LINE !!
#

MLD_SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
cd "${MLD_SCRIPT_DIR}"

# Helpers
function LOG {
    echo -e "\033[35m\033[1m[LOG] ${1}\033[0m\n"
}
function ERROR {
    echo -e "\033[0;31m\033[1m[ERROR] ${1}\033[0m\n"
    exit 1
}
# --Helpers

function check_privileges {
    if [[ "$(id -u)" -eq 0 ]]; then
        echo "####################################"
        echo "This script MUST NOT be run as root!"
        echo "####################################"
        exit 1
    fi

    sudo echo ""
    [[ ${?} -eq 0 ]] || LOG "Your root password is wrong"
}

function init_script {
    # Install packages dependencies
    if [[ ! -x "$(command -v git)" || ! -x "$(command -v rustup)" || ! -x "$(command -v flatpak)" ]]; then
        sudo pacman -S --needed --noconfirm git rustup flatpak ||
            ERROR "Unable to install required dependencies"
    fi

    # Init rustup
    if [[ ! $(rustup toolchain list) =~ "stable" ]]; then
        rustup install stable || ERROR "Unable to configure rustup"
    fi
    if [[ -z "$(rustup default)" ]]; then
        rustup default stable || ERROR "Unable to configure rustup"
    fi

    # Install paru
    if [[ ! -x "$(command -v paru)" ]]; then
        git clone https://aur.archlinux.org/paru.git "${MLD_SCRIPT_DIR}/paru" &&
            cd "${MLD_SCRIPT_DIR}/paru" && makepkg -si --noconfirm --needed ||
            ERROR "Unable to install paru"
        rm -r "${MLD_SCRIPT_DIR}/paru"
    fi

    # Init flatpak
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo ||
        ERROR "Unable to configure flatpak"
}

function install_packages {
    (
        set +e
        source "${MLD_MANAGE_PACKAGES_SCRIPT_PATH}"
        set -e

        # Install pacman packages
        if [[ "${MLD_OUTPUT_PACKAGES_INSTALL[@]}" != "" ]]; then
            sudo pacman -S --needed --noconfirm ${MLD_OUTPUT_PACKAGES_INSTALL[@]} ||
                ERROR "Unable to install pacman '${MLD_OUTPUT_PACKAGES_INSTALL[@]}'"
        fi
        # Remove pacman packages
        if [[ "${MLD_OUTPUT_PACKAGES_REMOVE[@]}" != "" ]]; then
            sudo pacman -Rcns ${MLD_OUTPUT_PACKAGES_REMOVE[@]} ||
                ERROR "Unable to remove pacman '${MLD_OUTPUT_PACKAGES_REMOVE[@]}'"
        fi

        # Install aur packages
        for _package in ${MLD_OUTPUT_AUR_PACKAGES_INSTALL[@]}; do
            paru -S --noconfirm --noprovides --skipreview "${_package}" ||
                ERROR "Unable to install aur '${_package}'"
        done
        # Remove aur packages
        for _package in ${MLD_OUTPUT_AUR_PACKAGES_REMOVE[@]}; do
            paru -Rcns --noconfirm "${_package}" ||
                ERROR "Unable to remove aur '${_package}'"
        done

        # Install flatpaks
        for _package in ${MLD_OUTPUT_FLATPAKS_INSTALL[@]}; do
            flatpak install -y "${_package}" ||
                ERROR "Unable to install flatpak '${_package}'"
        done
        # Remove flatpaks
        for _package in ${MLD_OUTPUT_FLATPAKS_REMOVE[@]}; do
            flatpak uninstall -y "${_package}" ||
                ERROR "Unable to remove flatpak '${_package}'"
        done
    )
}

function save_packages {
    set +e
    source "${MLD_MANAGE_PACKAGES_SCRIPT_PATH}" true
    set -e
}

check_privileges
init_script
install_packages
save_packages
