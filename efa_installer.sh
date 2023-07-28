#!/bin/bash
# Copyright 2019-2022 Amazon.com, Inc. or its affiliates. All Rights Reserved.

# Installation script for the Elastic Fabric Adapter.

source ./env.sh

if [ "${EFA_INSTALLER_VERSION}" = "" ]; then
	echo "Installer version is not defined in env.sh" >&2
	exit 1
fi

DIR=$(dirname "$0")
LIBFABRIC_INSTALL_PATH="/opt/amazon/efa"
OPENMPI_INSTALL_PATH="/opt/amazon/openmpi"
EFA_PROFILE_PATH="/etc/profile.d/efa.sh"
EFA_LDCONF_PATH="/etc/ld.so.conf.d/efa.conf"
EFA_PCI_PREFIX="1d0f:efa"
RDMA_CORE_PKGS="ibacm infiniband-diags  infiniband-diags-compat libibumad libibverbs libibverbs-utils librdmacm librdmacm-utils rdma-core rdma-core-devel rdma-core-debuginfo"

PREV_INSTALLED_PKGS_FILE="/opt/amazon/efa/installed_packages"
INSTALLED_PKGS_FILE="/opt/amazon/efa_installed_packages"
declare -a INSTALLED_PKGS
declare -a INSTALLED_KERNELS

DBG_PKGS=0
UNINSTALL=0
UNATTENDED=0
NO_VERIFY=0
SKIP_LIMITS=0
NEED_REBOOT=0
SKIP_KMOD=0
MINIMAL=0

usage() {
	cat <<EOF
usage: $(basename "$0") [options]

Options:
 -d, --debug-packages	Install debug packages
 -u, --uninstall	Uninstall EFA packages
 -y, --yes		Run installer without prompting for confirmation
 -n, --no-verify	Skip EFA device verification and test
 -l, --skip-limit-conf	Skip EFA limit configuration
 -k, --skip-kmod	Skip EFA kmod installation
 -g, --enable-gdr       Enable GPUDirect RDMA support. This option is not needed as the support is enabled by default.
 -m, --minimal          Only install kernel module and rdma-core, do not install openmpi and libfabric
EOF
}

detect_os() {
	if is_amazon_linux_2 || is_centos_7 || is_rhel_7 || is_rhel_8 || is_rockylinux_8 || is_rockylinux_9; then
		PACKAGE_TYPE="rpm"
		KERNEL_SEARCH_STRING=kernel
		INSTALL_ARGS="--setopt=skip_missing_names_on_install=False"
		UPDATE_INITRAMFS="dracut -f"
	elif is_suse_15; then
		PACKAGE_TYPE="rpm"
		KERNEL_SEARCH_STRING=kernel-default
		INSTALL_ARGS=""
		UPDATE_INITRAMFS="mkinitrd"
	elif is_debian_10 || is_debian_11 || is_ubuntu_2004 || is_ubuntu_2204; then
		PACKAGE_TYPE="deb"
		export DEBIAN_FRONTEND=noninteractive
		UPDATE_INITRAMFS="update-initramfs -u -k all"
	elif is_centos_8; then
		cat >&2 <<EOF
EFA installer with version >= 1.15.0 does not support CentOS 8 as the distro version has reached end of life (https://www.centos.org/centos-linux-eol/).
Refer EFA documentation (https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/efa.html#efa-amis) for more details on supported OSes.
EOF
		exit 1
	else
		cat >&2 <<EOF
Unsupported operating system.
Refer EFA documentation (https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/efa.html#efa-amis) for more details on supported OSes.
EOF
		exit 1
	fi
}

exit_sles15_efa_unsupported_module() {
	cat >&2 <<EOF

==============================================================================
SUSE Linux Enterprise Server does not load out of tree kernel modules by default. To avoid tainting the kernel re-run the installer with --skip-kmod to use the in-tree EFA kernel module instead of using the kernel module bundled with this installer. Using the in-tree module may lead to certain EFA features being disabled depending on which EFA kernel driver version is bundled with your operating system.
==============================================================================

EOF
	exit 1
}

exit_kernel_hdr_not_installed() {
	cat >&2 <<EOF

==============================================================================
The kernel header of the current kernel version cannot be installed and is required
to build the EFA kernel module. Please install the kernel header package for your
distribution manually or build the EFA kernel driver manually and re-run the installer
with --skip-kmod.
==============================================================================

EOF
	exit 1
}

detect_kernels() {
	if [ "${PACKAGE_TYPE}" = "rpm" ]; then
		for kernel in $(rpm -q ${KERNEL_SEARCH_STRING} | sed "s/${KERNEL_SEARCH_STRING}-//"); do
			INSTALLED_KERNELS+=("${kernel}")
		done
	elif [ "${PACKAGE_TYPE}" = "deb" ]; then
		# Skip the linux-image-* metapackages when searching for
		# installed kernels, we're interested in the kernel version
		# string.
		for kernel in $(dpkg-query -W --showformat='${Package}\n' \
			'linux-image-*' | grep -E -v 'linux-image-[[:alpha:]]' |
			sed 's/linux-image-//'); do
			INSTALLED_KERNELS+=("${kernel}")
		done
	fi

	if [ "${#INSTALLED_KERNELS[*]}" -eq 0 ]; then
		echo "Error: unable to detect installed kernels, exiting." >&2
		exit 1
	fi
}

detect_architecture() {
	arch=$(uname -m)
	if [ ! "$arch" = "x86_64" ] && [ ! "$arch" = "aarch64" ]; then
		echo "Error: unknown architecture, exiting." >&2
		exit 1
	fi
}

ubuntu_kernel_version_check() {
	if is_ubuntu_2004 || is_ubuntu_2204; then
		if [ ! -n "$(find /lib/modules/$(uname -r) -type f -name 'ib_uverbs.ko')" ]; then
			cat <<EOF
== Kernel version checking ==
Your Ubuntu AMI launches with a kernel which does not include the ib_uverbs kernel module, which is necessary for EFA support.
Canonical has published a new kernel in the Ubuntu ${VERSION_ID} repositories which includes the ib_ubverbs kernel module.

EOF

			if [ ${UNATTENDED} -ne 1 ]; then
				prompt "We will run command 'DEBIAN_FRONTEND=noninteractive apt-get -y --with-new-pkgs -o Dpkg::Options::=\"--force-confdef\" -o Dpkg::Options::=\"--force-confold\" upgrade' to upgrade the kernel, and the system will be rebooted automatically after the kernel upgrade!! Do you want to continue?" || exit 1
				DEBIAN_FRONTEND=noninteractive apt-get -y --with-new-pkgs -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" upgrade
				echo "After reboot, you can run ./efa_test.sh to locally test EFA connectivity with fi_pingpong test."
				reboot
			else
				cat <<EOF
Please run the following commands to upgrade the kernel. Note that the system will be rebooted after kernel upgrade!!
$ sudo DEBIAN_FRONTEND=noninteractive apt-get -y --with-new-pkgs -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" upgrade
$ sudo reboot
After reboot, you can run ./efa_test.sh to locally test EFA connectivity with fi_pingpong test.
EOF
				exit 1
			fi
		fi
	fi
}

setup_install_package_paths() {
	local base_dir
	local debug_dir
	local kmod_path

	if [ "${PACKAGE_TYPE}" = "rpm" ]; then
		if is_centos_7 || is_rhel_7; then
			base_dir="RPMS/CENT7/${arch}"
			debug_dir="RPMS/CENT7/${arch}/debug"
		elif is_rhel_8; then
			base_dir="RPMS/RHEL8/${arch}"
			debug_dir="RPMS/RHEL8/${arch}/debug"
		elif is_rockylinux_8; then
			base_dir="RPMS/ROCKYLINUX8/${arch}"
			debug_dir="RPMS/ROCKYLINUX8/${arch}/debug"
		elif is_rockylinux_9; then
			base_dir="RPMS/ROCKYLINUX9/${arch}"
			debug_dir="RPMS/ROCKYLINUX9/${arch}/debug"
		elif is_amazon_linux_2; then
			base_dir="RPMS/ALINUX2/${arch}"
			debug_dir="RPMS/ALINUX2/${arch}/debug"
		elif is_suse_15; then
			base_dir="RPMS/SUSE/${arch}"
			debug_dir="RPMS/SUSE/${arch}/debug"
		else
			echo "Error: unknown OS." >&2
			exit 1
		fi
	elif [ "${PACKAGE_TYPE}" = "deb" ]; then
		if is_debian_10; then
			base_dir="DEBS/DEBIAN10/${arch}"
			debug_dir="DEBS/DEBIAN10/${arch}/debug"
		elif is_debian_11; then
			base_dir="DEBS/DEBIAN11/${arch}"
			debug_dir="DEBS/DEBIAN11/${arch}/debug"
		elif is_ubuntu_2004; then
			base_dir="DEBS/UBUNTU2004/${arch}"
			debug_dir="DEBS/UBUNTU2004/${arch}/debug"
		elif is_ubuntu_2204; then
			base_dir="DEBS/UBUNTU2204/${arch}"
			debug_dir="DEBS/UBUNTU2204/${arch}/debug"
		else
			echo "Error: unknown OS." >&2
			exit 1
		fi
	fi

	if [ ! -d "${base_dir}" ]; then
		echo "Error: package directory ${base_dir} does not exist." >&2
		exit 1
	fi

	if [ ! -d "${debug_dir}" ]; then
		echo "Error: package directory ${debug_dir} does not exist." >&2
		exit 1
	fi

	PACKAGE_PATHS=$(echo ${base_dir}/*.${PACKAGE_TYPE})
	PACKAGE_PATHS="${PACKAGE_PATHS} ${base_dir}/rdma-core/*.${PACKAGE_TYPE}"

	kmod_path=$(echo ${base_dir}/efa-driver/*.${PACKAGE_TYPE})
	if [ ${SKIP_KMOD} -eq 0 ]; then
		PACKAGE_PATHS="${PACKAGE_PATHS} ${kmod_path}"
	fi

	if [ ${DBG_PKGS} -eq 1 ]; then
		PACKAGE_PATHS="${PACKAGE_PATHS} ${debug_dir}/*.${PACKAGE_TYPE}"
		PACKAGE_PATHS="${PACKAGE_PATHS} ${debug_dir}/rdma-core/*.${PACKAGE_TYPE}"
	fi
	package_array=($PACKAGE_PATHS)
	for i in "${package_array[@]}"; do
		if ! grep -Fxq "$i" package_list.txt; then
			echo "Error: unknown package found: $i"
			echo "Please remove unknown packages from the RPMS/DEBS directory trees"
			exit 1
		fi
	done
	if [ "${PACKAGE_TYPE}" = "deb" ]; then
		PACKAGE_PATHS=$(printf "${DIR}/%s " "${package_array[@]}")
	fi
}

read_package_file() {
	for pkg in $(grep -v '^#' ${INSTALLED_PKGS_FILE}); do
		INSTALLED_PKGS+=("$pkg")
	done
}

write_package_file() {
	mkdir -p /opt/amazon

	debug="no"
	if [ ${DBG_PKGS} -eq 1 ]; then
		debug="yes"
	fi

	rm -rf ${PREV_INSTALLED_PKGS_FILE}

	cat <<EOF >${INSTALLED_PKGS_FILE}
# EFA installer version: ${EFA_INSTALLER_VERSION}
# Debug packages installed: ${debug}
# Packages installed:
${INSTALLED_PKGS[*]}
EOF
	return $?
}

efa_installed() {
	if ! [ -f "${INSTALLED_PKGS_FILE}" ]; then
		return 1
	fi

	if grep -q "Debug packages installed: yes" "${INSTALLED_PKGS_FILE}"; then
		DBG_PKGS=1
	fi

	return 0
}

unload_efa_kmod() {
	local loaded=$(lsmod | grep ^efa | wc -l)
	if [ "${loaded}" -eq 1 ]; then
		echo "Unloading EFA kernel module"
		if ! rmmod efa; then
			echo "Failed to unload EFA kernel module."
			echo "Reboot is needed!" >&2
			NEED_REBOOT=1
		fi
	fi
}

dkms_installed() {
	if search_cmd "dkms" >/dev/null 2>&1; then
		return 0
	fi
	return 1
}

efa_config_installed() {
	if search_cmd efa-config 2>/dev/null | grep -q efa-config; then
		return 0
	fi
	return 1
}

# package_installed() is used to check if a package listed in /opt/amazon/efa_installed_packages
# is installed, which contains the versions and architecture in its name. It should not be used
# to check if packages with general names like efa, dkms are installed.
# In those cases, "search_cmd <package_name>" should be used.
package_installed() {
	local package="$1"

	if [ "${PACKAGE_TYPE}" = "rpm" ]; then
		if search_cmd "${package}" >/dev/null 2>&1; then
			echo "${package} already installed"
			return 0
		fi
	elif [ "${PACKAGE_TYPE}" = "deb" ]; then
		local package_name=$(echo ${package} | cut -d '_' -f 1)
		local package_version=$(echo ${package} | cut -d '_' -f 2)
		local installed_version=$(search_cmd 2>/dev/null | grep "^${package_name}" | awk '{print $2}')
		if [ "${package_version}" = "${installed_version}" ]; then
			echo "${package} already installed"
			return 0
		fi
	fi
	return 1
}

# package_should_be_skipped() takes the path of local package as the argument.
# It first queries the local package's name and version.
# Then it uses search_cmd() to query the version of same package that has already been installed
# Do version comparison to determine if we need to skip installing local package.
package_should_be_skipped() {
	local pkg_path="$1"
	local pkg_name=""
	local pkg_ver=""
	local installed_pkg_ver=""

	if [ "${PACKAGE_TYPE}" = "rpm" ]; then
		pkg=$(basename "${pkg_path}")
		pkg_name=$(rpm -qp --qf "%{NAME}\n" $pkg_path)
		pkg_ver=$(rpm -qp --qf "%{VERSION}-%{RELEASE}\n" $pkg_path)
		installed_pkg_ver=$(rpm -qa --qf "%{VERSION}-%{RELEASE}\n" $pkg_name)
		if is_suse_15; then
			ret=$(zypper --terse versioncmp "${pkg_ver}" "${installed_pkg_ver:-0}")
		else
			rpmdev-vercmp "${pkg_ver}" "${installed_pkg_ver:-0}" 1>/dev/null
			ret=$?
		fi
		# if installed_pkg_ver is higher to pkg_ver, skip the installation.
		# For suse, ret = -1; for others, ret = 12;
		if [ $ret -eq 12 ] || [ $ret -eq -1 ]; then
			echo "${pkg_name}-${installed_pkg_ver} already installed"
			return 0
		fi
	elif [ "${PACKAGE_TYPE}" = "deb" ]; then
		pkg=$(basename "${pkg_path}")
		pkg_name=$(echo ${pkg} | cut -d '_' -f 1)
		pkg_ver=$(echo ${pkg} | cut -d '_' -f 2)
		installed_pkg_ver=$(search_cmd 2>/dev/null | grep "^${pkg_name}\/" | awk '{print $2}')
		if dpkg --compare-versions "${pkg_ver}" "le" "${installed_pkg_ver}"; then
			echo "${pkg_name}_${installed_pkg_ver} already installed"
			return 0
		fi
	fi
	return 1
}

install_packages() {
	if ! install_cmd ${INSTALL_ARGS} $@; then
		echo "Error: Failed to install packages." >&2
		return 1
	fi
	return 0
}

install_apt_package() {
	local package="$1"
	if ! apt-get install -y ${package}; then
		echo "Error: Failed to install package ${package}" >&2
		return 1
	fi
	return 0
}

install_dependencies() {
	local packages

	if is_amazon_linux_2 || is_centos_7 || is_rhel_7 || is_rhel_8 || is_rockylinux_8 || is_rockylinux_9; then
		packages="pciutils rpmdevtools"
		if [ ${SKIP_KMOD} -eq 0 ]; then
			for kernel in ${INSTALLED_KERNELS[@]}; do
				if ! install_packages kernel-devel-${kernel}; then
					if is_kernel_current "${kernel}"; then
						exit_kernel_hdr_not_installed
					else
						echo "Kernel header for kernel: ${kernel} is not installed"
					fi
				fi
			done
		fi
		install_packages "${packages}" || return 1
	elif is_suse_15; then
		if [ ${SKIP_KMOD} -eq 0 ]; then
			INSTALL_ARGS="--oldpackage"
			for kernel in ${INSTALLED_KERNELS[@]}; do
				if ! install_packages kernel-default-devel-${kernel}; then
					if is_kernel_current "${kernel}"; then
						exit_kernel_hdr_not_installed
					else
						echo "Kernel header for kernel: ${kernel} is not installed"
					fi
				fi
			done
			INSTALL_ARGS=""
		fi
		# SUSE AMIs require installing make for efa kmod
		install_packages pciutils make || return 1
	elif is_debian_10 || is_debian_11 || is_ubuntu_2004 || is_ubuntu_2204; then
		packages="pciutils environment-modules tcl libnl-3-200 libnl-3-dev libnl-route-3-200 libnl-route-3-dev"
		if [ ${SKIP_KMOD} -eq 0 ]; then
			packages="${packages} dkms"
			for kernel in ${INSTALLED_KERNELS[@]}; do
				# Strip 'unsigned' prefix/suffix from kernel string since
				# header package names don't include 'unsigned'
				local suffix
				suffix=${kernel%-unsigned}
				suffix=${suffix#unsigned-}
				if ! install_packages "linux-headers-${suffix}"; then
					if is_kernel_current "${kernel}"; then
						exit_kernel_hdr_not_installed
					else
						echo "Kernel header for kernel: ${kernel} is not installed"
					fi
				fi
			done
		fi
		install_packages "${packages}" || return 1
	fi
}

uninstall_efa_packages() {
	if [ "${#INSTALLED_PKGS[*]}" -eq 0 ]; then
		return 0
	fi

	unload_efa_kmod

	if [ "${PACKAGE_TYPE}" = "rpm" ]; then
		if ! remove_cmd ${INSTALLED_PKGS[@]}; then
			echo "Error: Failed to remove packages." >&2
			return 1
		fi
	elif [ "${PACKAGE_TYPE}" = "deb" ]; then
		local installed_pkg_names=()
		local installed_pkg_names_purge=()
		for pkg in ${INSTALLED_PKGS[@]}; do
			local pkg_name=$(echo ${pkg} | cut -d '_' -f 1)

			if [[ ${pkg_name} = *"efa-config"* ]] ||
				[[ ${pkg_name} = *"efa-profile"* ]]; then
				installed_pkg_names_purge+=("$pkg_name")
			else
				installed_pkg_names+=("$pkg_name")
			fi
		done
		if ! remove_cmd 1 ${installed_pkg_names_purge[@]}; then
			echo "Error: Failed to remove packages" >&2
			return 1
		fi
		if ! remove_cmd ${installed_pkg_names[@]}; then
			echo "Error: Failed to remove packages" >&2
			return 1
		fi
	fi

	INSTALLED_PKGS=()

	if [ -f "${INSTALLED_PKGS_FILE}" ]; then
		rm "${INSTALLED_PKGS_FILE}"
	fi

	return 0
}

install_efa_packages() {
	local pkgs=()
	local rdmacore_pkgs=()

	for package_path in ${PACKAGE_PATHS}; do
		if ! [ -f "${package_path}" ]; then
			echo "Error: ${package_path} does not exist." >&2
			return 1
		fi

		package_name="$(basename "${package_path}")"
		if [ "${PACKAGE_TYPE}" = "rpm" ]; then
			package_name="${package_name%.rpm}"
		elif [ "${PACKAGE_TYPE}" = "deb" ]; then
			package_name="${package_name%.deb}"
		fi

		# Check for debuginfo package conflicts on rpm based systems.
		# Debian names its debug packags as 'dbg' instead of
		# 'debuginfo'. The Debian dbg packages will not conflict so a
		# check is not needed.
		if [[ ${package_name} == *"debuginfo"* ]]; then
			rpm -qa | grep -q ${package_name}
			if [ $? -ne 0 ]; then
				rpm -i --test ${package_path}
				if [ $? -ne 0 ]; then
					echo "debuginfo package ${package_name} will" \
						"fail to install. Please remove existing" \
						"debuginfo packages related to" \
						"${package_name}" >&2
					exit 1
				fi
			fi
		fi

		if [ ${SKIP_LIMITS} -eq 1 ] &&
			[[ ${package_name} = *"efa-config"* ]]; then
			continue
		fi

		if [ ${SKIP_KMOD} -eq 1 ] && [[ ${package_name} = *"efa"* ]] &&
			[[ ${package_name} != *"libefa"* ]] &&
			[[ ${package_name} != *"efa-config"* ]] &&
			[[ ${package_name} != *"efa-profile"* ]]; then
			continue
		fi

		if [ ${MINIMAL} -eq 1 ]; then
			if [[ ${package_name} = *"libfabric"* ||
				${package_name} = *"openmpi"* ||
				${package_name} = *"efa-profile"* ]]; then
				echo skipping ${package_name} because of minimal installation
				continue
			fi
		fi

		# If dkms is already installed, skip the installation
		if [[ ${package_name} = "dkms"* ]] && dkms_installed; then
			echo "dkms is already installed"
			continue
		fi

		INSTALLED_PKGS+=("${package_name}")

		if package_installed "${package_name}" || package_should_be_skipped "${package_path}"; then
			continue
		fi

		# As rdma-core packages have dependency with each other,
		# group them into $rdmacore_pkgs. And other packages are
		# in $pkgs
		if [[ "$package_path" = *"rdma-core"* ]]; then
			rdmacore_pkgs+=("${package_path}")
		else
			pkgs+=("${package_path}")
		fi

		# unload existing EFA kernel module if we are going to install
		# a new one
		if [ "$(echo ${package_name} | cut -c 1-3)" = "efa" ] &&
			[[ ${package_name} != *"efa-config"* ]] &&
			[[ ${package_name} != *"efa-profile"* ]]; then
			unload_efa_kmod
		fi
	done

	if [ "${#rdmacore_pkgs[*]}" -ne 0 ]; then
		echo Installing ${rdmacore_pkgs}
		if is_suse_15; then
			INSTALL_ARGS="--allow-unsigned-rpm"
		elif is_debian_10 || is_debian_11 || is_ubuntu_2004 || is_ubuntu_2204; then
			INSTALL_ARGS="--allow-downgrades"
		fi
		if ! install_packages ${rdmacore_pkgs[@]}; then
			return 1
		fi
	fi

	if [ "${#pkgs[*]}" -ne 0 ]; then
		echo Installing ${pkgs}
		if is_suse_15; then
			INSTALL_ARGS="--allow-unsigned-rpm"
		elif is_debian_10 || is_debian_11 || is_ubuntu_2004 || is_ubuntu_2204; then
			# clear up "--allow-downgrade" set for rdma-core packages above
			INSTALL_ARGS=""
		fi
		if ! install_packages ${pkgs[@]}; then
			return 1
		fi
	fi

	if ! write_package_file; then
		echo "Error: failed to write installed packages file." >&2
		return 1
	fi

	if [ ${SKIP_KMOD} -eq 0 ]; then
		echo "Updating boot ramdisk"
		if ! ${UPDATE_INITRAMFS}; then
			echo "Error: failed to generate new initramfs image, reboot OS might load old EFA kernel modules." >&2
			return 1
		fi
	fi

	return 0
}

uninstall_efa() {
	local ret=0

	if ! efa_installed; then
		echo "Error: EFA is not installed, exiting." >&2
		exit 1
	fi

	read_package_file

	echo "== Uninstalling EFA packages =="
	if ! uninstall_efa_packages; then
		echo "Error: failed to uninstall EFA packages, please remove them manually." >&2
		ret=1
	fi

	echo ""
	if [ $ret -eq 0 ]; then
		echo "EFA uninstall complete."
	else
		echo "EFA uninstall encountered errors, please check output." >&2
	fi

	return $ret
}

uninstall_old_efa_packages() {
	# Uninstall 'openmpi' and 'libfabric' if packaged by AWS.
	if is_amazon_linux_2 || is_centos_7 || is_rhel_7 || is_rhel_8 || is_rockylinux_8 || is_rockylinux_9; then
		for pkg in openmpi libfabric libfabric-debuginfo; do
			rpm -ql $pkg | grep -q /opt/amazon
			if [ $? -eq 0 ]; then
				remove_cmd $pkg
			fi
		done
	elif is_debian_10 || is_debian_11 || is_ubuntu_2004 || is_ubuntu_2204; then
		for pkg in openmpi libfabric1; do
			dpkg-query -W --showformat='${Maintainer}\n' $pkg \
				2>/dev/null | grep -q ec2-efa-maintainers
			if [ $? -eq 0 ]; then
				remove_cmd -y $pkg
			fi
		done
	fi

	# Skip cleaning up old files if this is a clean installation.
	if ! [ -f "$INSTALLED_PKGS_FILE" ]; then
		return 0
	fi

	# Clean up old configure files if efa-config package is not present. The
	# efa-config package now handles system limits required for EFA.
	#
	# This limits uninstall script will do nothing if the limits
	# configuration was skipped during install.
	if [ "$PACKAGE_TYPE" = "deb" ]; then
		efa_config_pkg=$(cat "$INSTALLED_PKGS_FILE" |
			tr ' ' '\n' | grep "^efa-config")
	else
		efa_config_pkg="efa-config"
	fi
	if ! package_installed $efa_config_pkg; then
		if ! (./efa_uninstall_limits.sh); then
			echo "Error: failed to remove old system limits files." >&2
		fi

		if ! rm -f "${EFA_PROFILE_PATH}"; then
			echo "Error: failed to remove ${EFA_PROFILE_PATH}" >&2
		fi

		if ! rm -f "${EFA_LDCONF_PATH}"; then
			echo "Error: failed to remove ${EFA_LDCONF_PATH}" >&2
		fi
	fi
}

install_efa() {
	# If skip limits has been set and we are in an upgrade path remove
	# efa-config before installing.
	if [ ${SKIP_LIMITS} -eq 1 ] && efa_config_installed; then
		echo "Skip EFA limits set, uninstalling efa-config"
		local ret=0
		if [ "${PACKAGE_TYPE}" = "rpm" ]; then
			remove_cmd efa-config
			ret=$?
		elif [ "${PACKAGE_TYPE}" = "deb" ]; then
			remove_cmd 1 efa-config
			ret=$?
		fi
		if [ ${ret} -ne 0 ]; then
			echo "Error: failed to remove efa-config package, please manually remove before installing, exiting" >&2
			exit 1
		fi
	fi
	echo "== Installing EFA dependencies =="
	if ! install_dependencies; then
		echo "Error: failed to install third-party dependencies, exiting" >&2
		exit 1
	fi

	echo "== Installing EFA packages =="
	if ! install_efa_packages; then
		echo "Error: failed to install EFA packages, exiting" >&2
		exit 1
	fi
}

test_efa() {
	if [ ${NO_VERIFY} -eq 1 ]; then
		return
	fi

	if [ ${MINIMAL} -eq 1 ]; then
		echo "Minimal installation does not include libfabric, skipping test."
		return
	fi

	if ! lspci -n | grep -q "${EFA_PCI_PREFIX}"; then
		echo "EFA device not detected, skipping test."
		return
	fi

	echo "== Testing EFA device =="

	. "${EFA_PROFILE_PATH}"

	# When the EFA driver is reloaded the device gets registered as efa_0.
	# At that point the persistent naming udev rule kicks in and renames the device.
	# fi_info can precede the udev rule so libibverbs will still use efa_0 as the device name,
	# but when ibv_query_gid() is called the sysfs path is already renamed.
	#
	# This should be solved in newer versions of the kernel and rdma-core
	# as sysfs is no longer used for device discovery and gid querying.
	#
	# Tries fi_info and sleeps between attempts to wait for the udev rule to apply.
	#
	end=$((SECONDS + 15))
	while ! command -v fi_info >/dev/null 2>&1 && ! fi_info -p efa >/dev/null 2>&1 && [ ${SECONDS} -lt $end ]; do
		sleep 1
	done

	./efa_test.sh
}

echo "= Starting Amazon Elastic Fabric Adapter Installation Script ="
echo "= EFA Installer Version: ${EFA_INSTALLER_VERSION} ="
echo ""

if [ ! -e common.sh ]; then
	echo "Please cd into the installer directory." >&2
	exit 1
fi

if [ -f common.sh ]; then
	. common.sh
else
	echo "Error: unable to load common functions." >&2
	exit 1
fi
detect_architecture

TEMP=$(getopt -o :dnuylkmg --long debug-packages,no-verify,uninstall,yes,skip-limit-conf,skip-kmod,minimal,enable-gdr -- "$@")
if [[ $? -ne 0 ]]; then
	usage
	exit 1
fi

eval set -- "$TEMP"
unset TEMP

while true; do
	case "$1" in
	'-d' | '--debug-packages')
		DBG_PKGS=1
		shift
		continue
		;;
	'-u' | '--uninstall')
		UNINSTALL=1
		shift
		continue
		;;
	'-y' | '--yes')
		UNATTENDED=1
		shift
		continue
		;;
	'-n' | '--no-verify')
		NO_VERIFY=1
		shift
		continue
		;;
	'-l' | '--skip-limit-conf')
		SKIP_LIMITS=1
		shift
		continue
		;;
	'-k' | '--skip-kmod')
		SKIP_KMOD=1
		shift
		continue
		;;
	'-m' | '--minimal')
		MINIMAL=1
		shift
		continue
		;;
	'-g' | '--enable-gdr')
		shift
		continue
		;;
	'--')
		shift
		break
		;;
	*)
		echo "$@"
		usage
		exit 1
		;;
	esac
done

if is_suse_15 && [ "$NAME" = "SLES" ] && [ ${SKIP_KMOD} -eq 0 ]; then
	exit_sles15_efa_unsupported_module
fi
is_root
detect_os

if is_centos_7 || is_rhel_7; then
	if [ "$arch" = "aarch64" ] && [ "$SKIP_KMOD" -eq 0 ]; then
		echo " An EFA kernel driver on this operating system for the Arm architecture is not available in this version of the installer." >&2
		exit 1
	fi
fi

if [ ${SKIP_KMOD} -eq 0 ]; then
	detect_kernels
fi

if [ ${UNINSTALL} -eq 1 ]; then
	if [ ${UNATTENDED} -ne 1 ]; then
		prompt "Please confirm that you would like to uninstall EFA" || exit 1
	fi
	uninstall_efa
	exit $?
fi

if efa_installed; then
	if [ ${UNATTENDED} -ne 1 ]; then
		prompt "EFA is already installed. Would you like to reinstall EFA?" || exit 1
	fi
else
	if [ ${UNATTENDED} -ne 1 ]; then
		prompt "This script will install the EFA kernel driver and required user space packages. Do you wish to continue?" || exit 1
	fi
fi

setup_install_package_paths
uninstall_old_efa_packages
install_efa
if [ ${SKIP_KMOD} -eq 0 ]; then
	ubuntu_kernel_version_check
	modprobe ib_core
	modprobe ib_uverbs

	# DKMS has a bug which will cause older version of
	# EFA kernel driver being loaded during installation
	# See this GitHub issue for more details:
	#
	#    https://github.com/dell/dkms/issues/143
	#
	# Before this issue is resolved, we will need to
	# unload and reload EFA kernel module.
	#
	unload_efa_kmod
	echo "Reloading EFA kernel module"
	modprobe efa
fi

test_efa

if [ $? -ne 0 ]; then
    if [ ${MINIMAL} -eq 1 ]; then
        cat <<EOF
===================================================
EFA installation is complete and an EFA device has
been detected but a ping test failed. Please consult
the EFA documentation to verify your configuration.
===================================================
EOF

    else
        cat <<EOF
===================================================
EFA installation is complete and an EFA device has
been detected but a ping test failed. Please consult
the EFA documentation to verify your configuration.
- Libfabric was installed in ${LIBFABRIC_INSTALL_PATH}
- Open MPI was installed in ${OPENMPI_INSTALL_PATH}
===================================================
EOF
    fi

    exit 1
fi

if [ ${NEED_REBOOT} -eq 1 ]; then
	action="reboot"
else
	action="logout/login"
fi

if [ ${MINIMAL} -eq 1 ]; then
	cat <<EOF
===================================================
EFA installation complete.
- Please ${action} to complete the installation.
===================================================
EOF

else
	cat <<EOF
===================================================
EFA installation complete.
- Please ${action} to complete the installation.
- Libfabric was installed in ${LIBFABRIC_INSTALL_PATH}
- Open MPI was installed in ${OPENMPI_INSTALL_PATH}
===================================================
EOF

fi
