# Sources
MUSL_SOURCE := git://git.musl-libc.org/musl
BUSYBOX_SOURCE := git://busybox.net/busybox.git
LINUX_SOURCE := git://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git

# Configuration
BUSYBOX_CONFIG := busybox.config
ROOTFS_OVERLAYDIR := rootfs-overlay
LINUX_CONFIG := linux.config
BOOTFS_LABEL := BOOT
BOOTFS_SIZE := 1440
BOOTFS_CREATE_GPT := 0
QEMU_CMD := qemu-system-x86_64 -bios /usr/share/ovmf/x64/OVMF.fd -smp 2

# Temporary directories
ROOTFS_DIR := rootfs
BOOTFS_MOUNTDIR := floppy

# Recipe targets
MUSL_DIR := musl
MUSL_BUILD_DIR := musl-build
MUSL_GCC := $(MUSL_BUILD_DIR)/bin/musl-gcc
BUSYBOX_DIR := busybox
BUSYBOX := $(BUSYBOX_DIR)/busybox
ROOTFS_CPIO := rootfs.cpio
LINUX_DIR := linux
LINUX_HEADERS_DIR := linux-headers
LINUX_BZIMAGE := $(LINUX_DIR)/arch/x86/boot/bzImage
BOOTFS_IMAGE := floppy.img

.PHONY: all configure source update clean reset
all: $(BOOTFS_IMAGE)
configure: musl-configure busybox-configure linux-configure
source: $(MUSL_DIR) $(BUSYBOX_DIR) $(LINUX_DIR)
update: musl-update busybox-update linux-update
clean: musl-clean busybox-clean rootfs-clean linux-clean bootfs-clean
reset:
	rm -rf "$(MUSL_DIR)" "$(MUSL_BUILD_DIR)" "$(BUSYBOX_DIR)" "$(LINUX_DIR)" \
		"$(LINUX_HEADERS_DIR)" "$(ROOTFS_DIR)" "$(ROOTFS_CPIO)" \
		"$(BOOTFS_MOUNTDIR)" "$(BOOTFS_IMAGE)"

$(MUSL_DIR):
	git clone --depth=1 "$(MUSL_SOURCE)" "$(MUSL_DIR)"

$(MUSL_BUILD_DIR): | $(LINUX_HEADERS_DIR)
	rm -rf "$(MUSL_BUILD_DIR)"

	mkdir "$(MUSL_BUILD_DIR)" \
		"$(MUSL_BUILD_DIR)"/bin \
		"$(MUSL_BUILD_DIR)"/include \
		"$(MUSL_BUILD_DIR)"/lib

# These symlinks ensure that programs and headers required for building BusyBox
# under musl are present (besides musl-gcc).
# Refer: https://www.openwall.com/lists/musl/2014/08/08/13
	ln -s "$$(which as)" "$(MUSL_BUILD_DIR)"/bin/musl-as
	ln -s "$$(which ar)" "$(MUSL_BUILD_DIR)"/bin/musl-ar
	ln -s "$$(which nm)" "$(MUSL_BUILD_DIR)"/bin/musl-nm
	ln -s "$$(which strip)" "$(MUSL_BUILD_DIR)"/bin/musl-strip
	ln -s "$$(which objcopy)" "$(MUSL_BUILD_DIR)"/bin/musl-objcopy
	ln -s "$$(which objdump)" "$(MUSL_BUILD_DIR)"/bin/musl-objdum
	ln -s "$$(which pkg-config)" "$(MUSL_BUILD_DIR)"/bin/musl-pkg-config
	ln -s "../../$(LINUX_HEADERS_DIR)/include/linux" "$(MUSL_BUILD_DIR)"/include/linux
	ln -s "../../$(LINUX_HEADERS_DIR)/include/mtd" "$(MUSL_BUILD_DIR)"/include/mtd
	ln -s "../../$(LINUX_HEADERS_DIR)/include/asm" "$(MUSL_BUILD_DIR)"/include/asm
	ln -s "../../$(LINUX_HEADERS_DIR)/include/asm-generic" "$(MUSL_BUILD_DIR)"/include/asm-generic

$(MUSL_GCC): | $(MUSL_DIR) $(MUSL_BUILD_DIR)
	$(MAKE) -C "$(MUSL_DIR)" -j "$$(nproc)" all
	$(MAKE) -C "$(MUSL_DIR)" install

.PHONY: musl-update
musl-update: $(MUSL_DIR)
	git -C "$(MUSL_DIR)" pull

.PHONY: musl-configure
musl-configure: $(MUSL_DIR)
	cd "$(MUSL_DIR)" && ./configure --prefix=../"$(MUSL_BUILD_DIR)"

.PHONY: musl-clean
musl-clean:
	[ -d "$(MUSL_DIR)" ] && $(MAKE) -C "$(MUSL_DIR)" distclean
	rm -rf "$(MUSL_BUILD_DIR)"

$(BUSYBOX_DIR):
	git clone --depth=1 "$(BUSYBOX_SOURCE)" "$(BUSYBOX_DIR)"

$(BUSYBOX): $(BUSYBOX_DIR)/.config $(MUSL_GCC) | $(BUSYBOX_DIR)
	$(MAKE) -C "$(BUSYBOX_DIR)" -j "$$(nproc)" CC=../$(MUSL_GCC) all

.PHONY: busybox-update
busybox-update: $(BUSYBOX_DIR)
	git -C "$(BUSYBOX_DIR)" pull

.PHONY: busybox-configure
busybox-configure: $(BUSYBOX_DIR)
	cp "$(BUSYBOX_CONFIG)" "$(BUSYBOX_DIR)"/.config
	$(MAKE) -C "$(BUSYBOX_DIR)" CC=../$(MUSL_GCC) oldconfig

.PHONY: busybox-clean
busybox-clean:
	[ -d "$(BUSYBOX_DIR)" ] && $(MAKE) -C "$(BUSYBOX_DIR)" distclean

# https://www.kernel.org/doc/Documentation/admin-guide/devices.txt
define _ROOTFS_BUILD_CMDS :=
set -e
rm -rf "$(ROOTFS_DIR)"
mkdir "$(ROOTFS_DIR)" "$(ROOTFS_DIR)"/root "$(ROOTFS_DIR)"/bin "$(ROOTFS_DIR)"/sbin "$(ROOTFS_DIR)"/dev "$(ROOTFS_DIR)"/proc "$(ROOTFS_DIR)"/etc "$(ROOTFS_DIR)"/sys "$(ROOTFS_DIR)"/tmp
$(MAKE) -C "$(BUSYBOX_DIR)" CC=../$(MUSL_GCC) CONFIG_PREFIX=../"$(ROOTFS_DIR)" install
mknod "$(ROOTFS_DIR)"/dev/null c 1 3
mknod "$(ROOTFS_DIR)"/dev/zero c 1 5
mknod "$(ROOTFS_DIR)"/dev/random c 1 8
mknod "$(ROOTFS_DIR)"/dev/urandom c 1 9
mknod "$(ROOTFS_DIR)"/dev/tty0 c 4 0
mknod "$(ROOTFS_DIR)"/dev/tty1 c 4 1
mknod "$(ROOTFS_DIR)"/dev/tty2 c 4 2
mknod "$(ROOTFS_DIR)"/dev/tty3 c 4 3
mknod "$(ROOTFS_DIR)"/dev/tty c 5 0
ln -s /proc/self/fd/0 "$(ROOTFS_DIR)"/dev/stdin
ln -s /proc/self/fd/1 "$(ROOTFS_DIR)"/dev/stdout
ln -s /proc/self/fd/2 "$(ROOTFS_DIR)"/dev/stderr
cp -rfv "$(ROOTFS_OVERLAYDIR)"/* "$(ROOTFS_DIR)"
cd "$(ROOTFS_DIR)" && find . | cpio -H newc -o > ../"$(ROOTFS_CPIO)"
rm -rf "$(ROOTFS_DIR)"
endef
export ROOTFS_BUILD_CMDS := $(value _ROOTFS_BUILD_CMDS)
$(ROOTFS_CPIO): $(BUSYBOX) $(ROOTFS_OVERLAYDIR)
# We don't need actual root privileges for this operation.
	echo "$${ROOTFS_BUILD_CMDS}" | fakeroot

.PHONY: rootfs-clean
rootfs-clean:
	rm -rf "$(ROOTFS_DIR)" "$(ROOTFS_CPIO)"

$(LINUX_DIR):
	git clone --depth=1 "$(LINUX_SOURCE)" "$(LINUX_DIR)"

$(LINUX_HEADERS_DIR): | $(LINUX_DIR)
	$(MAKE) -C "$(LINUX_DIR)" \
		headers_install INSTALL_HDR_PATH=../"$(LINUX_HEADERS_DIR)"

$(LINUX_BZIMAGE): $(LINUX_DIR)/.config $(ROOTFS_CPIO) | $(LINUX_DIR)
	$(MAKE) -C "$(LINUX_DIR)" -j "$$(nproc)" bzImage

.PHONY: linux-update
linux-update: $(LINUX_DIR)
	git -C "$(LINUX_DIR)" pull

.PHONY: linux-configure
linux-configure: $(LINUX_DIR)
	cp "$(LINUX_CONFIG)" "$(LINUX_DIR)"/.config
	$(MAKE) -C "$(LINUX_DIR)" oldconfig

.PHONY: linux-clean
linux-clean:
	[ -d "$(LINUX_DIR)" ] && $(MAKE) -C "$(LINUX_DIR)" distclean
	rm -rf "$(LINUX_HEADERS_DIR)"

define _BOOTFS_BUILD_CMDS :=
set -e
losetup -j "$(BOOTFS_IMAGE)" | cut -d ':' -f 1 | xargs -r losetup -d
if [ "$(BOOTFS_CREATE_GPT)" = 1 ]; then
	sgdisk -a 2 -N -t 1:EF00
	loopdev="$$(losetup -P -f "$(BOOTFS_IMAGE)" --show)"p1
else
	loopdev="$$(losetup -f "$(BOOTFS_IMAGE)" --show)"
fi
mkfs.fat -F 12 -n "$(BOOTFS_LABEL)" "$${loopdev}"
mountpoint -q "$(BOOTFS_MOUNTDIR)" && umount "$(BOOTFS_MOUNTDIR)"
mount -m "$${loopdev}" "$(BOOTFS_MOUNTDIR)"
mkdir -p "$(BOOTFS_MOUNTDIR)"/EFI/BOOT
cp "$(LINUX_BZIMAGE)" "$(BOOTFS_MOUNTDIR)"/EFI/BOOT/BOOTX64.EFI
umount "$(BOOTFS_MOUNTDIR)"
rmdir "$(BOOTFS_MOUNTDIR)"
losetup -d "$${loopdev%p1}"
endef
export BOOTFS_BUILD_CMDS := $(value _BOOTFS_BUILD_CMDS)
$(BOOTFS_IMAGE): $(LINUX_BZIMAGE)
	dd if=/dev/zero of="$(BOOTFS_IMAGE)" \
		bs=1024 count="$(BOOTFS_SIZE)" conv=fsync
# losetup, mount and mkfs.fat likely require actual root privileges.
	echo "$${BOOTFS_BUILD_CMDS}" | sudo -s

.PHONY: bootfs-clean
bootfs-clean:
	rm -f "$(BOOTFS_IMAGE)"

.PHONY: runqemu-bzImage
runqemu-bzImage:
	$(QEMU_CMD) -kernel "$(LINUX_BZIMAGE)"

.PHONY: runqemu-floppy.img
runqemu-$(BOOTFS_IMAGE):
# QEMU's UEFI implementation doesn't seem to support booting from an internal
# FDD, so we simulate an external USB-connected drive instead.
	$(QEMU_CMD) \
		-drive id=usbstick,if=none,file="$(BOOTFS_IMAGE)",format=raw \
		-usb \
		-device usb-ehci,id=ehci \
		-device usb-storage,bus=ehci.0,drive=usbstick,bootindex=1
