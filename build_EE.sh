#!/usr/bin/env bash

##
# EmptyEpsilon Linux build script
# Version: 1.0.2
# Date: 2017-08-02
# Author: Ben Landin <github.com/blandin>, <blastyr.net>
# License: GNU General Public License, Version 2
#          <https://github.com/blandin/EmptyEpsilon-linux-buildscript/blob/master/LICENSE>
#
# The purpose of this Bash script is to facilitate and expedite the process of
# building EmptyEpsilon on Linux platforms. <https://daid.github.io/EmptyEpsilon/>
##

# Configuration (recommended to be left alone)
BS_BASE_DIR="$(readlink -f "$(dirname "${0}")")"
BS_NAME="$(basename "${0}")"
BS_LOG_FILE="${BS_BASE_DIR}/build_EE.$(date +'%Y%m%d_%H%M%S').log"

BS_EE_DIR="${BS_BASE_DIR}/EmptyEpsilon"
BS_EE_GIT="https://github.com/daid/EmptyEpsilon.git"

BS_SP_DIR="${BS_BASE_DIR}/SeriousProton"
BS_SP_GIT="https://github.com/daid/SeriousProton.git"

BS_BUILD_DIR="${BS_BASE_DIR}/EmptyEpsilon_build"


if [ "${1}" = "--help" ]; then
	echo "Usage: ${BS_NAME} [options] [git_release_tag [version_number]]"
	echo "Options:"
	echo "  -e | --elevate"
	echo "      Prompt for sudo password without preliminary prompt"
	echo "  -E | --no-elevate"
	echo "      Do not elevate; disables build environment updating and installing"
	echo "  -f | --full-build-env-update"
	echo "      Forces a full update of the build environment; implies --elevate"
	echo "  -u | --update-source"
	echo "      For existing repositories, updates source code from git"
	echo "  -b | --build"
	echo "      Build without prompting once build environment is verified"
	echo "  -B | --no-build"
	echo "      Do not build after verifying build environment"
	echo "  -i | --install"
	echo "      Install without prompting after building; implies --build and --elevate"
	echo "  -I | --no-install"
	echo "      Do not install after building"
	echo "  --no-compat-check"
	echo "      Disable distribution compatibility checks"
	echo "Examples:"
	echo "  ${BS_NAME} -f -u -b"
	echo "  ${BS_NAME} -i EE-2017.01.19"
	exit 0
fi


# Functions
function mecho {
	local pre=""
	local ec=""
	while [[ ${1} == -* ]]; do case "${1}" in
		"-e")	pre="WARN";;
		"-f")	pre="FATAL";;
		"-i")	pre="INFO";;
		"-p")	pre="${2}"; shift;;
		"-x")	ec=${2}; shift;;
	esac; shift; done
	[ -n "${pre}" ] && echo -n "[${pre}] "
	echo "${1}"; shift
	while [ -n "${1}" ]; do echo "${1}"; shift; done
	[ -n "${ec}" ] && exit ${ec}
}
function error { mecho -e "$@"; }
function fatal { mecho -x 100 -f "$@"; }
function sudono { error "User chose not to elevate. Feature not enabled."; return 1; }
function sepln { echo "###############################################################################"; sleep 0.1s; }
function isyn { [[ "${1}" =~ ^[YyNn]$ ]]; }
function isy { [[ "${1}" =~ ^[Yy]$ ]]; }
function isn { [[ "${1}" =~ ^[Nn]$ ]]; }


# Recurse once to capture output for logging
log_flag="--logging-recurse"
if [ "${1}" = "${log_flag}" ]; then shift; else
	if touch "${BS_LOG_FILE}"; then
		$0 ${log_flag} "$@" | tee "${BS_LOG_FILE}"
		ec=${PIPESTATUS[0]}
		mecho -i "Log file written to: ${BS_LOG_FILE}"
		exit ${ec}
	else
		error "Can't write to log file ${BS_LOG_FILE}"
	fi
fi


# Set default behavior and parse behavior flags
do_compat_check="y"
do_env_update="n"
do_git_pull="n"
do_elevate=""
do_build=""
do_install=""
while [[ ${1} == -* ]]; do
	case "${1}" in
		"-e"|"--elevate")				do_elevate="y";;
		"-E"|"--no-elevate")			do_elevate="n";;
		"-f"|"--full-build-env-update")	do_elevate="y"; do_env_update="y";;
		"-u"|"--update-source")			do_git_pull="y";;
		"-b"|"--build")					do_build="y";;
		"-B"|"--no-build")				do_build="n";;
		"-i"|"--install")				do_elevate="y"; do_build="y"; do_install="y";;
		"-I"|"--no-install")			do_install="n";;
		"--no-compat-check")			do_compat_check="n";;
	esac
	shift
done

# Check distro and version
if isy "${do_compat_check}" && (which lsb_release > /dev/null || [ -f /etc/lsb-release ]); then
	if which lsb_release > /dev/null; then
		DISTRIB_ID="$("lsb_release" -si 2> /dev/null)"
		DISTRIB_RELEASE="$("lsb_release" -sr 2> /dev/null)"
	else
		source /etc/lsb-release
	fi

	compat_distros=('[Uu]buntu' '^Peppermint$')
	compat_minvers=('16.04' '8')

	compat="n"
	for (( i=0; i<${#compat_distros[@]}; i++ )); do
		if isn "${compat}" &&
		echo "${DISTRIB_ID}" | "grep" -P "${compat_distros[${i}]}" > /dev/null &&
		(( $(echo "${DISTRIB_RELEASE}"'>='"${compat_minvers[${i}]}" | bc -l) )); then
			compat="y"
		fi
	done
	isn "${compat}" && fatal "This script is not compatible with your distribution."
elif isn "${do_compat_check}"; then
	error "Compatibility check disabled. This script may not work as intended on your system."
else
	error "Unable to determine distribution compatibility! This script may not work as intended on your system."
fi


# Prompt once for elevation
me="$(whoami)"
sudo="sudono"
if [ "${me}" = "root" ]; then
	sudo=""
else
	if [ -z "${do_elevate}" ]; then
		echo "You may continue without elevating, however the following will be unavailable:" >&2
		echo "  - Installing/updating the build environment (if necessary)" >&2
		echo "  - Installing the build, once complete" >&2
		echo >&2
	fi
	yn="${do_elevate}"
	while ! isyn "${yn}"; do
		read -p "Would you like to enable elevated functionality? (y/N) " yn
		if [ -z "${yn}" ]; then yn="n"; fi
	done
	sudo -k
	if isy "${yn}" && sudo echo "Elevated privileges granted."; then
		sudo="sudo"
	else
		error "Elevated features disabled"

		# Can't --install or --full-build-env-update if not elevated
		isy "${do_install}" && fatal "Elevation is required when using the --install flag"
		isy "${do_full_env_update}" && fatal "Elevation is required when using the --full-build-env-update flag"
	fi
fi


# Verify build environment is complete
sepln
echo "Checking build environment..."
pkglist="git build-essential libx11-dev cmake libxrandr-dev mesa-common-dev libglu1-mesa-dev libudev-dev libglew-dev libjpeg-dev libfreetype6-dev libopenal-dev libsndfile1-dev libxcb1-dev libxcb-image0-dev libsfml-dev"
if isy "${do_env_update}"; then
	${sudo} apt-get update 2>&1 && ${sudo} apt-get install ${pkglist} 2>&1 || fatal "Unable to install or update build environment"
else
	instlist=()
	for pkg in ${pkglist}; do
		ret="$(dpkg -l ${pkg} 2> /dev/null)"
		if [ $? -ne 0 ]; then instlist+=("${pkg}"); fi
	done
	if [ ${#instlist[@]} -gt 0 ]; then
		error "Build environment missing packages: ${instlist[@]}" "Will install"
		${sudo} apt-get install ${instlist[@]} 2> /dev/null || fatal "Unable to install build environment"
	fi
fi
echo "Build environment verified"


# Verify projects are cloned and clean
for proj in EE SP; do
	sepln
	cd "${BS_BASE_DIR}"
	bs_dirvar="BS_${proj}_DIR"
	bs_gitvar="BS_${proj}_GIT"
	if [ ! -d "${!bs_dirvar}/.git" ]; then
		echo "Cloning ${proj} project (this may take a while)..."
		if [ -d "${!bs_dirvar}" ]; then
			rm -r "${!bs_dirvar}" 2>&1 || fatal "Unable to remove ${!bs_dirvar} before cloning ${proj} repository"
		fi
		git clone "${!bs_gitvar}" "${!bs_dirvar}" || fatal "Unable to clone ${proj} repository at ${!bs_dirvar}"
	else
		echo "${proj} already cloned. Cleaning up..."
		cd "${!bs_dirvar}"
		git clean -dfx 2>&1 || fatal "Unable to clean local ${proj} repository"
		git checkout master &> /dev/null || fatal "Unable to checkout master branch in ${proj} repository"
		if isy "${do_git_pull}"; then
			echo "Pulling latest code..."
			git fetch --all 2>&1 || fatal "Unable to fetch updated commit references in ${proj} repository"
			git pull origin master 2>&1 || fatal "Unable to refresh the master branch in ${proj} repository"
		fi
	fi

	# Checkout a specific tag for building, if supplied
	if [ -n "${1}" ]; then
		BS_TARGET="${1}"
		cd "${!bs_dirvar}"
		echo "Checking out target: ${1}"
		git checkout ${1} &> /dev/null || fatal "Unable to checkout ${1} in ${proj} repository"
	else
		BS_TARGET="master"
	fi
done


# Clean the build directory
sepln
if [ -d "${BS_BUILD_DIR}" ]; then
	rm -rf "${BS_BUILD_DIR}" 2>&1 || fatal "Unable to remove old build directory at ${BS_BUILD_DIR}"
fi
mkdir -p "${BS_BUILD_DIR}" 2>&1 || fatal "Unable to create build directory at ${BS_BUILD_DIR}"

# Might need this
BS_VERSION_ORIG="$(date +'%Y%m%d')"
BS_VERSION="${BS_VERSION_ORIG}"

# Move into directory and configure build
echo "Preparing to build..."
cd "${BS_BUILD_DIR}"
cmake "${BS_EE_DIR}" -DSERIOUS_PROTON_DIR="${BS_SP_DIR}/" 2>&1 || fatal "Build configuration failed"

# Reconfigure version number, if supplied
if [ -n "${2}" ]; then
	BS_VERSION="${2}"
elif [[ "${1}" =~ ^EE-[0-9]{4}\.[0-9]{2}\.[0-9]{2}$ ]]; then
	BS_VERSION="$(echo "${1}" | sed -r 's/^EE-([0-9]{4})\.([0-9]{2})\.([0-9]{2})$/\1\2\3/')"
fi
if [ "${BS_VERSION}" != "${BS_VERSION_ORIG}" ]; then
	"grep" -l -r "${BS_VERSION_ORIG}" ./* | while read file; do "sed" -i -r "s/${BS_VERSION_ORIG}/${BS_VERSION}/g" "${file}"; done
fi

# Prompt for user confirmation
sepln
echo "EmptyEpsilon:"
echo "    Source directory: ${BS_EE_DIR}"
echo "    Target branch/tag: ${BS_TARGET}"
echo "    Version number: ${BS_VERSION}"
echo "SeriousProton:"
echo "    Source directory: ${BS_SP_DIR}"
echo "    Target branch/tag: ${BS_TARGET}"
echo
yn="${do_build}"
while ! isyn "${yn}"; do
	read -p "Proceed with build? (Y/n) " yn
	if [ -z "${yn}" ]; then yn="y"; fi
done
isn "${do_build}" && mecho -i -x 0 "Would build"
! isy "${yn}" && fatal "Build cancelled"

# Here we go
sepln
make || fatal "Build failed"
echo "Build successful"


# Prompt user to install
sepln
yn="${do_install}"
while ! isyn "${yn}"; do
	read -p "Install? (y/N) " yn
	if [ -z "${yn}" ]; then yn="n"; fi
done
! isy "${yn}" && mecho -x 0 "You can install manually later:" "  cd \"${BS_BUILD_DIR}\" && sudo make install" >&2

# Install
${sudo} make install 2>&1 || fatal "Installation failed" "You can install manually later:" "  cd \"${BS_BUILD_DIR}\" && sudo make install"
echo "Installation complete"
