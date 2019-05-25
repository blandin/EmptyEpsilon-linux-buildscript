#!/usr/bin/env bash

##
# EmptyEpsilon Linux build script
# Version:      1.1.0
# Release date: 2019-05-25
# Author:       Ben Landin <https://github.com/blandin>, <http://blastyr.net>
# License:      GNU General Public License, Version 2
#               <https://github.com/blandin/EmptyEpsilon-linux-buildscript/blob/master/LICENSE>
#
# The purpose of this Bash script is to facilitate and expedite the process of
# building EmptyEpsilon on Linux platforms. <https://daid.github.io/EmptyEpsilon/>
##


# Configuration (recommended to be left alone)
BS_BASE_DIR="$(readlink -f "$(dirname "${0}")")"
BS_NAME="$(basename "${0}")"
BS_LOG_FILE="${BS_BASE_DIR}/build_EE.$(date +'%Y%m%d_%H%M%S').log"

BS_APT_OPTIONS=""

BS_EE_DIR="${BS_BASE_DIR}/EmptyEpsilon"
BS_EE_GIT="https://github.com/daid/EmptyEpsilon.git"

BS_SP_DIR="${BS_BASE_DIR}/SeriousProton"
BS_SP_GIT="https://github.com/daid/SeriousProton.git"

BS_SFML_DIR="${BS_BASE_DIR}/SFML"
BS_SFML_GIT="https://github.com/SFML/SFML.git"
BS_SFML_TARGET="2.4.2"

BS_EE_BUILD_DIR="${BS_BASE_DIR}/EmptyEpsilon_build"
BS_SFML_BUILD_DIR="${BS_BASE_DIR}/SFML_build"

BS_EE_PKGLIST="git build-essential libx11-dev libxrandr-dev mesa-common-dev libglu1-mesa-dev libudev-dev libglew-dev libjpeg-dev libfreetype6-dev libopenal-dev libsndfile1-dev libxcb1-dev libxcb-image0-dev cmake gcc g++"
BS_EE_PKG_SFML="libsfml-dev"

BS_SFML_PKGLIST="libgl1-mesa-dev libflac-dev libogg-dev libvorbis-dev"

BS_TARGET="master"

BS_CLI_PARAMS=""


# Need to quickly iterate the command line options to look for --help so we can output before logging happens
help_cli_option="no"
for o in "$@"; do if [ "${o}" = "--help" ]; then help_cli_option=""; fi; done


# Command line help
if [ -z "${help_cli_option}" ]; then
	head -n 12 "${0}" | tail -n 9
	echo
	echo "Usage: ${BS_NAME} [options] [git_release_tag [version_number]]"
	echo "Options:"
	echo "  -e | --elevate"
	echo "      Prompt for sudo password without preliminary prompt"
	echo "  -E | --no-elevate"
	echo "      Do not elevate; disables build environment updating and installing"
	echo "  -s | --build-sfml"
	echo "      Build and install the SFML library from source; implies --elevate"
	echo "  --sfml-version=x.x.x"
	echo "      Build and install a specific version of SFML from source; implies --build-sfml"
	echo "  -S | --no-build-sfml"
	echo "      Use the SFML library (${BS_EE_PKG_SFML}) from your distribution repository"
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
	echo "  -y | --apt-yes"
	echo "      Automatically approve package updates/installation when verifying the build environment"
	echo "  --no-compat-check"
	echo "      Disable distribution compatibility checks"
	echo "git_release_tag:"
	echo "  If you supply the keyword 'latest' for this parameter, the newest release tag will be used"
	echo "Examples:"
	echo "  ${BS_NAME} -yufi"
	echo "  ${BS_NAME} --install EE-2017.01.19"
	echo "  ${BS_NAME} --sfml-version=2.5.1 EE-2019.05.21"
	echo "  ${BS_NAME} latest"
	exit 0
fi


# Script helper functions
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


# Recurse once to pass CLI options configured in header, if necessary
recurse_cli_flag="--default-cli-recurse"
if [ "${1}" = "${recurse_cli_flag}" ]; then shift; elif [ -n "${BS_CLI_PARAMS}" ]; then
	${0} ${recurse_cli_flag} ${BS_CLI_PARAMS} "$@"
	exit $?
fi


# Recurse once to capture output for logging
recurse_log_flag="--logging-recurse"
if [ "${1}" = "${recurse_log_flag}" ]; then shift; else
	if touch "${BS_LOG_FILE}"; then
		${0} ${recurse_log_flag} "$@" | tee "${BS_LOG_FILE}"
		ec=${PIPESTATUS[0]}
		mecho -i "Log file written to: ${BS_LOG_FILE}"
		exit ${ec}
	else
		error "Can't write to log file ${BS_LOG_FILE}"
	fi
fi


# Set behavior flag defaults
cli_options=()
do_compat_check="y"
do_build_sfml=""
do_env_update="n"
do_git_pull="n"
do_elevate=""
do_build=""
do_install=""


# Parse command line flags
while [[ ${1} == -* ]]; do
	if [[ ${1} == --* ]]; then
		cli_options+=("${1}")
	else
		while read -n 1 flag; do
			if [ -n "${flag}" ]; then
				cli_options+=("-${flag}")
			fi
		done <<< "${1:1}"
	fi
	shift
done


# Process command line options
for opt in "${cli_options[@]}"; do
	case "${opt}" in
		"-e"|"--elevate")				do_elevate="y";;
		"-E"|"--no-elevate")			do_elevate="n";;
		"-s"|"--build-sfml")			do_elevate="y"; do_build_sfml="y";;
		"--sfml-version="*)				do_elevate="y"; do_build_sfml="y"; BS_SFML_TARGET="${opt:15}";;
		"-S"|"--no-build-sfml")			do_build_sfml="n";;
		"-f"|"--full-build-env-update")	do_elevate="y"; do_env_update="y";;
		"-u"|"--update-source")			do_git_pull="y";;
		"-b"|"--build")					do_build="y";;
		"-B"|"--no-build")				do_build="n";;
		"-i"|"--install")				do_elevate="y"; do_build="y"; do_install="y";;
		"-I"|"--no-install")			do_install="n";;
		"-y"|"--apt-yes")				BS_APT_OPTIONS+=" -y";;
		"--no-compat-check")			do_compat_check="n";;
		*)								error "Ignoring unknown command line option: ${1}";;
	esac
done


# Check distro and version
if isy "${do_compat_check}" && (which lsb_release > /dev/null || [ -f /etc/lsb-release ]); then
	if which lsb_release > /dev/null; then
		DISTRIB_ID="$("lsb_release" -si 2> /dev/null)"
		DISTRIB_RELEASE="$("lsb_release" -sr 2> /dev/null)"
	else
		source /etc/lsb-release
	fi

	compat_distros=('[Uu]buntu' '^Peppermint$' 'Debian')
	compat_minvers=('16.04' '8' '9')

	compat="n"
	for (( i=0; i<${#compat_distros[@]}; i++ )); do
		if isn "${compat}" &&
		echo "${DISTRIB_ID}" | "grep" -P "${compat_distros[${i}]}" > /dev/null &&
		(( $(echo "${DISTRIB_RELEASE}"'>='"${compat_minvers[${i}]}" | bc -l) )) &&
		which apt-get > /dev/null && which dpkg > /dev/null; then
			compat="y"
		fi
	done
	isn "${compat}" && fatal "This script is not compatible with your distribution."
elif isn "${do_compat_check}"; then
	error "Compatibility check disabled. This script may not work as intended on your system."
else
	fatal "Unable to determine distribution compatibility! This script may not work as intended on your system."
fi


# Prompt once for elevation
me="$(whoami)"
sudo="sudono"
if [ "${me}" = "root" ]; then
	sudo=""
else
	yn="${do_elevate}"
	if ! isyn "${yn}"; then
		echo "You may continue without elevating, however the following will be unavailable:" >&2
		echo "  - Installing/updating the build environment (if necessary)" >&2
		echo "  - Building and installing SFML from source" >&2
		echo "  - Installing the build, once complete" >&2
		echo >&2
	fi
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


# Resolve SFML dependency
sepln
yn="${do_build_sfml}"
if ! isyn "${yn}"; then
	echo "EmptyEpsilon depends on a library called SFML. On many distributions, this library is present in the repository." >&2
	echo "However, in some cases the version in the repository is too old, and will cause build errors." >&2
	echo "This script can obtain the SFML source code and build it automatically, instead." >&2
	echo >&2
fi
while ! isyn "${yn}"; do
	read -p "Download and build SFML library from source? (y/N) " yn
	if [ -z "${yn}" ]; then yn="n"; fi
done
if isn "${yn}"; then
	mecho -i "Adding ${BS_EE_PKG_SFML} package to build environment dependencies"
	BS_EE_PKGLIST+=" ${BS_EE_PKG_SFML}"
else
	mecho -i "Adding the following packages to build environment dependencies:" "  ${BS_SFML_PKGLIST}"
	BS_EE_PKGLIST+=" ${BS_SFML_PKGLIST}"
fi
do_build_sfml="${yn}"


# Verify build environment is complete
sepln
echo "Checking build environment..."
if isy "${do_env_update}"; then
	${sudo} apt-get update 2>&1 && ${sudo} apt-get ${BS_APT_OPTIONS} install ${BS_EE_PKGLIST} 2>&1 || fatal "Unable to install or update build environment"
else
	instlist=()
	for pkg in ${BS_EE_PKGLIST}; do
		ret="$(dpkg -l ${pkg} 2> /dev/null)"
		if [ $? -ne 0 ]; then instlist+=("${pkg}"); fi
	done
	if [ ${#instlist[@]} -gt 0 ]; then
		error "Build environment missing packages: ${instlist[@]}" "Will install"
		${sudo} apt-get ${BS_APT_OPTIONS} install ${instlist[@]} 2> /dev/null || fatal "Unable to install build environment"
	fi
fi
echo "Build environment verified"


# Verify projects are cloned and clean
projects="EE SP"
if isy "${do_build_sfml}"; then projects+=" SFML"; fi
for proj in ${projects}; do
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
done


# Checkout a specific tag for building, if supplied
if [ -n "${1}" ]; then
	sepln
	if [ "${1}" = "latest" ]; then
		cd "${BS_EE_DIR}"
		BS_TARGET="$(git tag | "grep" -P '^EE-[0-9]{4}\.[0-9]{2}\.[0-9]{2}$' | sort | tail -n 1)"
	else
		BS_TARGET="${1}"
	fi
	for proj in EE SP; do
		echo "Checking out ${BS_TARGET} in ${proj} repository..."
		bs_dirvar="BS_${proj}_DIR"
		cd "${!bs_dirvar}"
		git checkout "${BS_TARGET}" &> /dev/null || fatal "Unable to checkout ${BS_TARGET} in ${proj} repository"
	done
fi


# Clean the build directory
if [ -d "${BS_EE_BUILD_DIR}" ]; then
	rm -rf "${BS_EE_BUILD_DIR}" 2>&1 || fatal "Unable to remove old build directory at ${BS_EE_BUILD_DIR}"
fi
mkdir -p "${BS_EE_BUILD_DIR}" 2>&1 || fatal "Unable to create build directory at ${BS_EE_BUILD_DIR}"

# Need a version number for today's build
BS_VERSION="$(date +'%Y%m%d')"

# Reconfigure version number, if supplied
if [ -n "${2}" ]; then
	BS_VERSION="${2}"
elif [[ "${BS_TARGET}" =~ ^EE-[0-9]{4}\.[0-9]{2}\.[0-9]{2}$ ]]; then
	BS_VERSION="$(echo "${BS_TARGET}" | sed -r 's/^EE-([0-9]{4})\.([0-9]{2})\.([0-9]{2})$/\1\2\3/')"
elif [[ "${1}" =~ ^EE-[0-9]{4}\.[0-9]{2}\.[0-9]{2}$ ]]; then
	BS_VERSION="$(echo "${1}" | sed -r 's/^EE-([0-9]{4})\.([0-9]{2})\.([0-9]{2})$/\1\2\3/')"
fi


# Prompt for user confirmation
sepln
echo "Build parameters:" >&2
if isy "${do_build_sfml}"; then
echo "    SFML:" >&2
echo "        Source directory: ${BS_SFML_DIR}" >&2
echo "        Target branch/tag: ${BS_SFML_TARGET}" >&2
fi
echo "    EmptyEpsilon:" >&2
echo "        Source directory: ${BS_EE_DIR}" >&2
echo "        Target branch/tag: ${BS_TARGET}" >&2
echo "        Version number: ${BS_VERSION}" >&2
echo "    SeriousProton:" >&2
echo "        Source directory: ${BS_SP_DIR}" >&2
echo "        Target branch/tag: ${BS_TARGET}" >&2
echo >&2
yn="${do_build}"
while ! isyn "${yn}"; do
	read -p "Proceed with build? (Y/n) " yn
	if [ -z "${yn}" ]; then yn="y"; fi
done
isn "${do_build}" && mecho -i -x 0 "Would build"
! isy "${yn}" && mecho -i -x 50 "Build cancelled"


# Build SFML from source
if isy "${do_build_sfml}"; then
	# Checkout latest release
	sepln
	cd "${BS_SFML_DIR}"
	echo "Checking out release ${BS_SFML_TARGET} of SFML..."
	git checkout "${BS_SFML_TARGET}" &> /dev/null || fatal "Unable to checkout ${BS_SFML_TARGET} in SFML repository"

	# Clean the build directory
	sepln
	if [ -d "${BS_SFML_BUILD_DIR}" ]; then
		rm -rf "${BS_SFML_BUILD_DIR}" 2>&1 || fatal "Unable to remove old build directory at ${BS_SFML_BUILD_DIR}"
	fi
	mkdir -p "${BS_SFML_BUILD_DIR}" 2>&1 || fatal "Unable to create build directory at ${BS_SFML_BUILD_DIR}"

	# Move into directory, configure, build
	echo "Preparing to build SFML..."
	cd "${BS_SFML_BUILD_DIR}"
	cmake "${BS_SFML_DIR}" 2>&1 || fatal "SFML build configuration failed"
	sepln
	make || fatal "SFML build failed"
	${sudo} make install || fatal "SFML installation failed"
	${sudo} ldconfig || fatal "SFML library linkage failed"
fi


# Here we go
sepln
echo "Preparing to build EE..."
cd "${BS_EE_BUILD_DIR}"
cmake "${BS_EE_DIR}" \
	-DSERIOUS_PROTON_DIR="${BS_SP_DIR}/" \
	-DCPACK_PACKAGE_VERSION_MAJOR=${BS_VERSION:0:4} \
	-DCPACK_PACKAGE_VERSION_MINOR=${BS_VERSION:4:2} \
	-DCPACK_PACKAGE_VERSION_PATCH=${BS_VERSION:6:2} 2>&1 || fatal "Build configuration failed"
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
! isy "${yn}" && mecho -x 0 "You can install manually later:" "  cd \"${BS_EE_BUILD_DIR}\" && sudo make install" >&2

# Install
${sudo} make install 2>&1 || fatal "Installation failed" "You can install manually later:" "  cd \"${BS_EE_BUILD_DIR}\" && sudo make install"
echo "Installation complete"
