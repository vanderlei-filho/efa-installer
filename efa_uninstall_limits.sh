#!/bin/bash
# Copyright 2020 Amazon.com, Inc. or its affiliates. All Rights Reserved.

# Removes the old EFA limits configuration files. This is now handled by the
# efa-config package.

. common.sh

EFA_HUGEPAGES_SCRIPT="/opt/amazon/efa/bin/efa_hugepages.sh"

uninstall_limits_conf() {
	efa_limits="/etc/security/limits.d/efa.conf"
	if [ -f ${efa_limits} ]; then
		rm "${efa_limits}"
	fi
}

uninstall_hugepages_rc_local() {
	rc="/etc/rc.local"
	efa_str="# Additional configuration for Amazon EFA"

	if [ ! -f "${rc}" ]; then
		return 0
	fi

	if ! grep -q "${efa_str}" "${rc}"; then
		return 0
	fi

	sed -i "/${efa_str}/,+1d" "${rc}"
	rm -f ${EFA_HUGEPAGES_SCRIPT}
}

generate_grub() {
	if is_amazon_linux_2 || is_centos_7 || is_rhel_7; then
		grub_cfg="/boot/grub2/grub.cfg"
		grub_cmd="grub2-mkconfig"
	else
		echo "Unknown operating system."
		exit 1
	fi

	if [ ! -f "${grub_cfg}" ]; then
		echo "${grub_cfg} not found."
		exit 1
	fi

	${grub_cmd} -o "${grub_cfg}"
	return $?
}

uninstall_hugepages_grub_generate() {
	grub_file="/etc/default/grub"
	efa_str="# Additional configuration for Amazon EFA"

	if [ ! -f "${grub_file}" ]; then
		return 0
	fi

	if ! grep -q "${efa_str}" ${grub_file}; then
		return 0
	fi

	sed -i "/${efa_str}/,+1d" "${grub_file}"

	generate_grub
	return $?
}

is_root

ret=0

if ! uninstall_limits_conf; then
	echo "Error removing limits file."
	ret=1
fi

if is_amazon_linux_2 || is_centos_7 || is_rhel_7; then
	uninstall_hugepages_rc_local
else
	echo "Unknown operating system."
	ret=1
fi

if is_amazon_linux_2 || is_centos_7 || is_rhel_7; then
	uninstall_hugepages_grub_generate
fi

exit $ret
