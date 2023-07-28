# Changelog

All notable changes to this project will be documented in this file.

## [1.24.1] - July 2023
- Upgrade libfabric to 1.18.1
- Upgrade efa driver to 2.5.0

## [1.24.0] - June 2023
- Ingest rdma-core 46.0
- Ingest efa driver 2.4.1
- Support Debian 11

## [1.23.1] - June 2023
- Ingest libfabric 1.18.0amzn2.0

## [1.23.0] - May 2023
- Add support for Debian 10
- Drop support for Ubuntu 18.04 LTS
- Upgrade efa-config package to 1.14
- Ingest libfabric 1.18.0amzn1.0

## [1.22.1] - March 2023
- Upgrade libfabric to 1.17.1

## [1.22.0] - February 2023
- Upgrade Open MPI to 4.1.5
- Upgrade libfabric to 1.17.0
- Upgrade efa-config package to 1.13

## [1.21.0] - December 2022
- Add support for Rocky Linux 9 OS
- Ingest efa driver 2.1.1
- Ingest libfabric 1.16.1amzn3.0
- Upgrade efa-config package to 1.12

## [1.20.0] - November 2022
- Add support for Rocky Linux 8 OS.
- Ingest efa driver 2.1.0.
- Ingest rdma-core 43.0.
- Ingest libfabric 1.16.1amzn1.0

## [1.19.0] - October 2022
- Ingest libfabric 1.16.0
- Build Open MPI with `--enable-orterun-prefix-by-default`

## [1.18.0] - August 2022
- Add support for Ubuntu22.04

## [1.17.3] - August 2022
- Update libfabric to 1.16.0~amzn4.0. The "~" indicates it is a pre-release version of libfabric 1.16.0.
- Extend post-installation pingpong test timeout to 20 seconds

## [1.17.2] - July 2022
- Update libfabric to 1.16.0~amzn3.0. The "~" indicates it is a pre-release version of libfabric 1.16.0.

## [1.17.1] - July 2022
- Update libfabric to 1.16.0~amzn2.0. The "~" indicates it is a pre-release version of libfabric 1.16.0.
- Disable the experimental net provider when building libfabric

## [1.17.0] - July 2022
- Update rdma-core to v41.0
- Update Open MPI to 4.1.4
- Update libfabric to 1.16.0~amzn1.0. The "~" indicates it is a pre-release version of libfabric 1.16.0.

## [1.16.0] - June 2022
- Update libfabric to 1.15.1amzn1.0, contains neuron library name change
- Upgrade efa-config to 1.10
- Exclude opx and rxd providers in the libfabric build

## [1.15.2] - May 2022
- Update libfabric to 1.14.1

## [1.15.1] - March 2022
- Update libfabric to 1.14.0amzn1.0

## [1.15.0] - Feburary 2022
- Fix a bug that cause installation fail on Open SuSE 15.3
- Drop support of Open SuSE 15.2 (as Open SuSE 15.2 reached end of life)
- Drop Support of CentOS 8 (as CentOS 8 reached end of life)
- Update libfabric to 1.14.0
- Update efa kernel driver to 1.16.0
- Update rdma-core to v39.0
- Update Open MPI to version 4.1.2.

## [1.14.1] - October 2021

- Update libfabric to 1.13.2amzn1.0.

## [1.14.0] - October 2021

- Ingest efa kernel driver 1.14.2.
- Make "-g, --enable-gdr" in efa_installer.sh as a no-op option as the latest efa kernel driver enables GDR support by default.
- Ingest rdma-core v37.0.
- Ingest libfabric 1.13.2.
- Add packages list and compare RPM/DEB to list during installation to prevent
  unknown package installations.
- Add sleep in installer script to wait for udev rule to apply after EFA driver reload.

## [1.13.0] - August 2021

- Update rdma-core to v35.0.
- Update libfabric to v1.13.0amzn1.0.
- Add EFA support for CentOS/RHEL 8 on Gravition2 platform.
- Add version comparison logic in installer script to skip the local
  package installation when there is one installed in system with
  higher version.

## [1.12.3] - July 2021

- Update EFA kernel module to 1.13.0.
- Update efa-config package to version 1.9. Improve the calculation of
  huge page reservation to handle large defaulted huge page size.

## [1.12.2] - June 2021

- Update EFA kernel module to 1.12.3.
- Build Open MPI debian packages with `--with-libevent=external`
  and `--with-hwloc=external`.
- Bump Open MPI rpm build ID to 2 to fix backward compatibility
  issue of HWLOC on CentOS 8.
- Remove the installation of kernel-devel and kernel-source
  packages on SLES15SP2 and openSUSE 15.2.

## [1.12.1] - May 2021

- Update Libfabric to version 1.11.2amzon1.1.
- Update EFA kernel module to version 1.12.1.

## [1.12.0] - May 2021

- Update Open MPI to version 4.1.1.
- Update Libfabric to version 1.11.2amzn1.0.
- Build rdma-core for Amazon Linux 2 using the same packaging
  configuration as the AL2 rdma-core.
- Do not force `-Wl,--enable-new-dtags` when building Open MPI RPMs.
- Build Open MPI with system libraries for hwloc and libevent.
- Update EFA kernel module to version 1.12.0
- Update efa-config package to version 1.8.  Improve the calculation
  of huge page reservation for long-lived instances.
- Update efa-profile package to version 1.5. Remove the open mpi collective
  tuning file that worked as a workaround to fix Open MPI 4.1.0 hang on P4d.
- Update rdma-core to v32.1.
- Drop support for Amazon Linux 1 and Ubuntu 16.04.

## [1.11.2] - February 2021

- Fix Open MPI hang when using Open MPI on P4d by changing the default
  algorithm used to implement MPI_BARRIER via a configuration file.
- Disable use of builtin atomics in Open MPI on ARM via
  `--disable-builtin-atomics` to work around compiler issue.

## [1.11.1] - December 2020

- Update Open MPI to version 4.1.0.
- Update efa-config package to version 1.7.  Improve calculation of huge page
  reservation count.
- Update efa-profile package to version 1.3.  Removes unneeded
  collectives decision file now that Open MPI 4.1.0 is used.

## [1.11.0] - December 2020

- Add support for Gravition2 platform.
- Update rdma-core to version 31.2amzn.
- Update Libfabric to version 1.11.1amzn1.0.
- Update efa-config to version 1.6.
- Update efa-profile to version 1.2.

## [1.10.1] - November 2020

- Add support for CentOS / RHEL 8.
- Add support for Ubuntu 20.04.
- Add support for SUSE Linux Enterprise 15.

## [1.10.0] - October 2020

- Add GPUDirect RDMA support for P4d platform.  Use `--enable-gdr`
  installer option to instal GDR-aware kernel module and userspace.
- Update EFA kernel module to version 1.10.2.
- Update rdma-core to version 31.amzn0.
- Update Libfabric to version 1.11.1.
- Update Open MPI to version 4.0.5.
- Update efa-config to version 1.5.
- Update efa-profile to version 1.1.  Includes improved Open MPI
  collectives decision file.

## [1.9.5] - September 2020

- Update efa-config to version 1.4.  Fixes bug in Open MPI collective
  decision file.

## [1.9.4] - July 2020

- Update Open MPI to version 4.0.3.
- Update Libfabric to version 1.10.1amazon1.1.
- Update rdma-core to version 28.amzn0.

## [1.9.3] - June 2020

- Update EFA kernel module to version 1.6.0.
- Update rdma-core to version 28.amzn0.
- Update Libfabric to version 1.10.1amzn1.1.
- Update efa-config to version 1.3.  Adds collectives tuning file for
  Open MPI.
- Skip dkms installation if it is already installed.
- Fix `--skip-kmod` installation mode to actually work.

## [1.8.4] - April 2020

- Move configuration files into efa-config and efa-profile packages so
  that they are tracked by the operating system package manager.
- Update Open MPI to version 4.0.3.

## [1.8.3] - February 2020

- Update EFA kernel module to version 1.5.1.
- Distributed DKMS on some platforms rather than relying on EPEL
  repositories for added installation reliability.
- On RHEL 7, install RPMs built on CentOS 7 instead of RPMs built on
  Amazon Linux 2.

## [1.8.2] - January 2020

- Revert rdma-core to version 25 due to a mismatch in device naming
  between kernel module and rdma-core.

## [1.8.1] - January 2020

- Update Libfabric to version 1.9.0amzn1.1.

## [1.8.0] - December 2019

- Update rdma-core to version 27.0.
- Update EFA kernel module to version 1.5.0.
- Update Libfabric to version 1.9.0amzn1.0.
- Add option `--minimal` to install just the EFA kernel module and
  rdma-core.

## [1.7.1] - December 2019

- Update Libfabric to version 1.8.1amzn1.3.

## [1.7.0] - November 2019

- Add Libfabric module file.
- Update Libfabric to version 1.8.1amzn1.1.

## [1.6.2] - October 2019

- Update Open MPI to version 1.6.2.

## [1.6.1] - October 2019

- Update Libfabric to version 1.8.1amzn1.0.
- Update Open MPI to version 4.0.1.
- Update rdma-core to version 26.0.

## [1.5.4] - September 2019

- Update EFA kernel module to version 1.4.1.

## [1.5.3] - September 2019

- Update EFA kernel module to version 1.3.1.
- Avoid installing kernel-devel or linux-headers packages unless
  installing the kernel driver.

## [1.5.1] - August 2019

- Only configure huge pages when EFA device is present.

## [1.5.0] - August 2019

- Update Libfabric to version 1.8.0amzn1.1.
- Update rmda-core to version 25.0.

## [1.4.1] - July 2019

- Add Libfabric and Open MPI library paths (`/opt/amazon/efa/lib64`
  and `/opt/amazon/efa/openmpi/lib`) to `/etc/ld.so.conf.d/efa.conf`
  to ensure the Open MPI and Libfabric shared libraries are properly
  located.

## [1.4.0] - July 2019

- Update EFA kernel module to version 1.3.0.
- Update Libfabric to version 1.8.0amzn1.0
- First release to support Intel MPI 2019 Update 4.
