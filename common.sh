# Copyright 2022 Amazon.com, Inc. or its affiliates. All Rights Reserved.

is_root() {
	if [[ $EUID -ne 0 ]]; then
		echo "This installer must be run as root."
		exit 1
	fi
}

prompt() {
	local prompt=$1
	local response

	printf "%s [y/n]: " "${prompt}"

	read -r response

	response="${response,,}"

	if [ "${response}" != 'y' ] && [ "${response}" != 'yes' ]; then
		echo "Exiting..."
		return 1
	fi
	return 0
}

version_larger_or_equal() {
	version_1=$1
	version_2=$2
	version_smaller=$(printf "$version_1\n$version_2" | sort -V | head -n 1)
	if [ "$version_smaller" = "$version_2" ]; then
		return 0
	else
		return 1
	fi
}

has_substring() {
	string="$1"
	substring="$2"

	# ${string#*$substring} - strip $string of the smallest prefix of pattern `*$substring`
	# Stripping should also work, i.e. ${string%"$substring"*}
	# Copied from https://tiny.amazon.com/rj6h3xs1/stacques2829howd
	# Works for POSIX shell
	if test "${string#*$substring}" != "$string"; then
		return 0 # $substring is in $string
	else
		return 1 # $substring is not in $string
	fi
}

is_amazon_linux_2() {
	. /etc/os-release
	if [ "$NAME" = "Amazon Linux" ] && [ "$VERSION_ID" = "2023" ]; then
		return 0
	else
		return 1
	fi
}

is_centos_7() {
	. /etc/os-release
	if has_substring "$NAME" "CentOS" && [ "$VERSION_ID" = "7" ]; then
		return 0
	else
		return 1
	fi
}

is_centos_8() {
	. /etc/os-release
	if has_substring "$NAME" "CentOS" && [ "$VERSION_ID" = "8" ]; then
		return 0
	else
		return 1
	fi
}

is_debian_10() {
	. /etc/os-release
	if has_substring "$NAME" "Debian" && [ "$VERSION_ID" = "10" ]; then
		return 0
	else
		return 1
	fi
}

is_debian_11() {
	. /etc/os-release
	if has_substring "$NAME" "Debian" && [ "$VERSION_ID" = "11" ]; then
		return 0
	else
		return 1
	fi
}

is_rhel_7() {
	. /etc/os-release
	if has_substring "$NAME" "Red Hat Enterprise Linux" &&
		echo $VERSION_ID | egrep -q '7\.[0-9]'; then
		return 0
	else
		return 1
	fi
}

is_rhel_8() {
	. /etc/os-release
	if has_substring "$NAME" "Red Hat Enterprise Linux" &&
		echo $VERSION_ID | egrep -q '8\.[0-9]'; then
		return 0
	else
		return 1
	fi
}

is_rockylinux_8() {
	if [ "$NAME" = "Rocky Linux" ] &&
		echo $VERSION_ID | egrep -q '8\.[0-9]'; then
		return 0
	else
		return 1
	fi
}

is_rockylinux_9() {
	if [ "$NAME" = "Rocky Linux" ] &&
		echo $VERSION_ID | egrep -q '9\.[0-9]'; then
		return 0
	else
		return 1
	fi
}

is_ubuntu_2004() {
	. /etc/os-release
	if [ "$NAME" = "Ubuntu" ] && [ "$VERSION_ID" = "20.04" ]; then
		return 0
	else
		return 1
	fi
}

is_ubuntu_2204() {
	. /etc/os-release
	if [ "$NAME" = "Ubuntu" ] && [ "$VERSION_ID" = "22.04" ]; then
		return 0
	else
		return 1
	fi
}

is_suse_15() {
	. /etc/os-release
	if [ "$NAME" = "openSUSE Leap" ]; then
		version_larger_or_equal "$VERSION_ID" "15.3"
		return $?
	elif [ "$NAME" = "SLES" ] && echo $VERSION_ID | egrep -q '15\.[0-9]'; then
		return 0
	else
		return 1
	fi
}

install_cmd() {
	if is_amazon_linux_2 || is_centos_7 || is_rhel_7 || is_centos_8 || is_rhel_8 || is_rockylinux_8 || is_rockylinux_9; then
		if [ $1 == "localinstall" ]; then
			shift
			if is_centos_8; then
				# centos8 has reached end of life, and all repos has expired.
				# Meanwhile, localinstall does not need repos either. Therefore
				# disable repos for centos8 only.
				yum -y localinstall --disablerepo appstream,baseos,powertools $@
			else
				yum -y localinstall $@
			fi
		else
			yum -y install $@
		fi
	elif is_suse_15; then
		zypper install -y --no-recommends $@
	elif is_debian_10 || is_debian_11 || is_ubuntu_2004 || is_ubuntu_2204; then
		apt install -y $@
	else
		echo "Error: unsupported operating system, exiting." >&2
		exit 1
	fi
}
search_cmd() {
	if is_amazon_linux_2 || is_centos_7 || is_rhel_7 || is_centos_8 || is_rhel_8 || is_rockylinux_8 || is_rockylinux_9; then
		yum list installed $@
	elif is_suse_15; then
		zypper search --installed-only --match-exact $@
	elif is_debian_10 || is_debian_11 || is_ubuntu_2004 || is_ubuntu_2204; then
		apt list --installed $@
	else
		echo "Error: unsupported operating system, exiting." >&2
		exit 1
	fi
}
remove_cmd() {
	if is_amazon_linux_2 || is_centos_7 || is_rhel_7 || is_centos_8 || is_rhel_8 || is_rockylinux_8 || is_rockylinux_9; then
		yum -y remove $@
	elif is_suse_15; then
		zypper remove -y $@
	elif is_debian_10 || is_debian_11 || is_ubuntu_2004 || is_ubuntu_2204; then
		#The first argument for purge on ubuntu is 1, for all other
		#cases it will be the package name
		ubuntu_remove_purge=$1
		shift
		if [ $ubuntu_remove_purge -eq 1 ]; then
			apt -y purge $@
		else
			apt -y remove $@
		fi
	else
		echo "Error: unsupported operating system, exiting." >&2
		exit 1
	fi
}
# Check if the given kernel is the current running one
is_kernel_current() {
	kernel=$1
	if is_suse_15; then
		kernel_version_check_string=$(uname -r | sed 's/-default//')
	else
		kernel_version_check_string=$(uname -r)
	fi
	if [[ "${kernel}" == "${kernel_version_check_string}" ]]; then
		return 0
	else
		return 1
	fi
}
