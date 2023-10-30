#!/bin/bash

MLD_PACKAGES_DIR="../packages"
MLD_CACHE_DIR="${MLD_PACKAGES_DIR}/.cache_packages"

declare -A MLD_PACKAGES
declare -A MLD_AUR_PACKAGES
declare -A MLD_FLATPAKS
declare -A MLD_CACHE_PACKAGES
declare -A MLD_CACHE_AUR_PACKAGES
declare -A MLD_CACHE_FLATPAKS

# Update working directory to this script path
MLD_SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
cd "${MLD_SCRIPT_DIR}"

# This function clears a set of package-related variables.
#
# Returns:
#   None, but resets the global variables to their default values.
function clear_vars {
    DISABLE=false
    PACKAGES=()
    DEPENDENCIES=()
    AUR_PACKAGES=()
    AUR_DEPENDENCIES=()
    FLATPAK_PACKAGES=()
    FLATPAK_DEPENDENCIES=()
}

# This function removes the parent directory from a given path.
#
# Arguments:
#   $1: The full path (path) from which the parent directory should be removed.
#   $2: The name of the parent directory (dirname) to be removed from the path.
#
# Returns:
#   A string (return_remove_parent_directory) representing the modified path.
function remove_parent_directory {
    return_remove_parent_directory=$(echo "${1/$2\//}")
}

# This function calculates the difference between two arrays.
#
# Arguments:
#   $1: An array (arr) from which the difference is calculated.
#   $2: An array (cnt) that is subtracted from the first array.
#
# Returns:
#   An array (return_count_array) containing the elements that are in the first array (arr)
#   but not in the second array (cnt).
function get_array_diff {
    declare -n arr=$1
    declare -n cnt=$2
    declare -A _count

    # Count the occurrence of each element in the first array
    for element in ${arr[@]}; do
        let _count["$element"]++
    done

    return_count_array=()

    # For each element in the second array, if it doesn't exist in the associative array,
    # add it to the result array (return_count_array)
    for element in ${cnt[@]}; do
        [[ ${_count[$element]} -eq 0 ]] || continue
        return_count_array+=($element)
    done
}

# This function sets the value of an associative array.
#
# Arguments:
#   $1: The name of the array (arr) to which the value will be set.
#   $2: The key (key) used in the associative array.
#   $3: The file path (filepath) used to create the index in the associative array.
#   $@: The values to be set in the array.
#
# Returns:
#   None, but modifies the global associative array referenced by $1.
function set_value {
    declare -n arr=$1
    index="$2?$3"
    # Shift the positional parameters to remove $1, $2 and $3
    shift 3
    arr["$index"]="$@"
}

# This function indexes packages by reading from configuration files.
# It skips files that do not end with '.conf' and files that contain spaces.
# For each valid configuration file, it sources the file, checks if the package is disabled,
# and if not, it removes the parent directory from the file path and sets values in various associative arrays.
#
# Globals:
#   MLD_PACKAGES_DIR: The directory containing the configuration files.
#   MLD_PACKAGES: An associative array to store package information.
#   MLD_AUR_PACKAGES: An associative array to store AUR package information.
#   MLD_FLATPAKS: An associative array to store Flatpak information.
#
# Returns:
#   None, but modifies the global associative arrays MLD_PACKAGES, MLD_AUR_PACKAGES, and MLD_FLATPAKS.
function indexing_packages {
    while IFS= read -r -d '' file; do
        [[ ${file} != *.conf ]] && continue
        if [[ "${file}" =~ \ |\' ]]; then
            echo "Skip '${file}' spaces are not allowed"
            continue
        fi

        # Source the configuration file and clear previous variables
        clear_vars
        source "${file}"

        # Skip the file if the package is disabled
        [[ "${DISABLE}" == true ]] && continue

        remove_parent_directory "${file}" "${MLD_PACKAGES_DIR}"

        # Set the values in the associative arrays
        set_value "MLD_PACKAGES" "pkgs" "${return_remove_parent_directory}" "${PACKAGES[@]}"
        set_value "MLD_PACKAGES" "deps" "${return_remove_parent_directory}" "${DEPENDENCIES[@]}"
        set_value "MLD_AUR_PACKAGES" "pkgs" "${return_remove_parent_directory}" "${AUR_PACKAGES[@]}"
        set_value "MLD_AUR_PACKAGES" "deps" "${return_remove_parent_directory}" "${AUR_DEPENDENCIES[@]}"
        set_value "MLD_FLATPAKS" "pkgs" "${return_remove_parent_directory}" "${FLATPAK_PACKAGES[@]}"
        set_value "MLD_FLATPAKS" "deps" "${return_remove_parent_directory}" "${FLATPAK_DEPENDENCIES[@]}"
    done < <(find ${MLD_PACKAGES_DIR} -type f -print0)
}

# This function saves the indexed packages into a cache file.
#
# Globals:
#   MLD_PACKAGES: An associative array storing package information.
#   MLD_AUR_PACKAGES: An associative array storing AUR package information.
#   MLD_FLATPAKS: An associative array storing Flatpak information.
#   MLD_CACHE_DIR: The file to save the cache to.
#
# Returns:
#   None, but creates or overwrites the MLD_CACHE_DIR file.
function save_indexing_cache {
    local _output="#!/bin/bash\ndeclare -A CONFIG_CACHE_PACKAGES"

    # Store each non-empty entry from the MLD_PACKAGES associative array into CONFIG_CACHE_PACKAGES
    for key in "${!MLD_PACKAGES[@]}"; do
        [[ ! -z "${MLD_PACKAGES[$key]}" ]] && _output+="\nCONFIG_CACHE_PACKAGES[${key}]=\"${MLD_PACKAGES[$key]}\""
    done
    _output+="\ndeclare -A CONFIG_CACHE_AUR_PACKAGES"

    # Store each non-empty entry from the MLD_AUR_PACKAGES associative array into CONFIG_CACHE_AUR_PACKAGES
    for key in "${!MLD_AUR_PACKAGES[@]}"; do
        [[ ! -z "${MLD_AUR_PACKAGES[$key]}" ]] && _output+="\nCONFIG_CACHE_AUR_PACKAGES[${key}]=\"${MLD_AUR_PACKAGES[$key]}\""
    done
    _output+="\ndeclare -A CONFIG_CACHE_FLATPAKS"

    # Store each non-empty entry from the MLD_FLATPAKS associative array into CONFIG_CACHE_FLATPAKS
    for key in "${!MLD_FLATPAKS[@]}"; do
        [[ ! -z "${MLD_FLATPAKS[$key]}" ]] && _output+="\nCONFIG_CACHE_FLATPAKS[${key}]=\"${MLD_FLATPAKS[$key]}\""
    done

    # Save the generated script into the MLD_CACHE_DIR file
    echo -e "${_output}" >"${MLD_CACHE_DIR}"
}

# This function indexes the cache by sourcing the cache file stored in MLD_CACHE_DIR.
#
# Globals:
#   MLD_CACHE_DIR: The file path of the cache file.
#   CONFIG_CACHE_PACKAGES: Associative array storing the cached package information.
#   CONFIG_CACHE_AUR_PACKAGES: Associative array storing the cached AUR package information.
#   CONFIG_CACHE_FLATPAKS: Associative array storing the cached Flatpak information.
#   MLD_CACHE_PACKAGES: Associative array to store the loaded package information.
#   MLD_CACHE_AUR_PACKAGES: Associative array to store the loaded AUR package information.
#   MLD_CACHE_FLATPAKS: Associative array to store the loaded Flatpak information.
#
# Returns:
#   None, but modifies the global associative arrays MLD_CACHE_PACKAGES, MLD_CACHE_AUR_PACKAGES, and MLD_CACHE_FLATPAKS.
function indexing_cache {
    [[ ! -f "${MLD_CACHE_DIR}" ]] && return

    # Source the cache file
    source "${MLD_CACHE_DIR}"

    # Load the cached package information into the MLD_CACHE_PACKAGES associative array
    for key in "${!CONFIG_CACHE_PACKAGES[@]}"; do
        MLD_CACHE_PACKAGES[$key]="${CONFIG_CACHE_PACKAGES[$key]}"
    done

    # Load the cached AUR package information into the MLD_CACHE_AUR_PACKAGES associative array
    for key in "${!CONFIG_CACHE_AUR_PACKAGES[@]}"; do
        MLD_CACHE_AUR_PACKAGES[$key]="${CONFIG_CACHE_AUR_PACKAGES[$key]}"
    done

    # Load the cached Flatpak information into the MLD_CACHE_FLATPAKS associative array
    for key in "${!CONFIG_CACHE_FLATPAKS[@]}"; do
        MLD_CACHE_FLATPAKS[$key]="${CONFIG_CACHE_FLATPAKS[$key]}"
    done
}

indexing_packages
indexing_cache
if [[ "${1}" = true ]]; then
    save_indexing_cache
fi

# Calculate the regular packages to be removed and installed
# MLD_OUTPUT_PACKAGES_REMOVE will store the regular packages to be removed
get_array_diff "MLD_PACKAGES" "MLD_CACHE_PACKAGES"
MLD_OUTPUT_PACKAGES_REMOVE="${return_count_array[@]}"
# MLD_OUTPUT_PACKAGES_INSTALL will store the regular packages to be installed
get_array_diff "MLD_CACHE_PACKAGES" "MLD_PACKAGES"
MLD_OUTPUT_PACKAGES_INSTALL="${return_count_array[@]}"

# Calculate the Aur packages to be removed and installed
# MLD_OUTPUT_AUR_PACKAGES_REMOVE will store the Aur packages to be removed
get_array_diff "MLD_AUR_PACKAGES" "MLD_CACHE_AUR_PACKAGES"
MLD_OUTPUT_AUR_PACKAGES_REMOVE="${return_count_array[@]}"
# MLD_OUTPUT_AUR_PACKAGES_INSTALL will store the Aur packages to be installed
get_array_diff "MLD_CACHE_AUR_PACKAGES" "MLD_AUR_PACKAGES"
MLD_OUTPUT_AUR_PACKAGES_INSTALL="${return_count_array[@]}"

# Calculate the Flatpaks to be removed and installed
# MLD_OUTPUT_FLATPAKS_REMOVE will store the Flatpaks to be removed
get_array_diff "MLD_FLATPAKS" "MLD_CACHE_FLATPAKS"
MLD_OUTPUT_FLATPAKS_REMOVE="${return_count_array[@]}"
# MLD_OUTPUT_FLATPAKS_INSTALL will store the Flatpaks to be installed
get_array_diff "MLD_CACHE_FLATPAKS" "MLD_FLATPAKS"
MLD_OUTPUT_FLATPAKS_INSTALL="${return_count_array[@]}"

return 0
