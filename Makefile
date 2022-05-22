# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2021, 2022 S. K. Medlock, E. K. Herman, K. M. Shaw
#
# Makefile cheat-sheet:
#
# $@ : target label
# $< : the first prerequisite after the colon
# $^ : all of the prerequisite files
# $* : wildcard matched part
#
# Setting Variables:
# https://www.gnu.org/software/make/manual/html_node/Setting.html
#
# Target-specific Variable syntax:
# https://www.gnu.org/software/make/manual/html_node/Target_002dspecific.html
#
# patsubst : $(patsubst pattern,replacement,text)
#       https://www.gnu.org/software/make/manual/html_node/Text-Functions.html

SHELL=/bin/bash

# 8.11.1 (Jessie LTS, for some arches only)
# 9.0.0 to 9.13.0 (Stretch)
# 10.0.0 to ... (Buster)
# 11.0.0 to ... (Bullseye)

DISTRO_ORIG_ISO=debian-10.12.0-amd64-netinst.iso
DISTRO_ISO_URL=https://cdimage.debian.org/mirror/cdimage/archive/10.12.0/amd64/iso-cd/debian-10.12.0-amd64-netinst.iso
ISO_TARGET=debian-10.12.0-autoinstall.iso
ISO_TARGET_VOLUME=debian-10.12.0-autoinstall
BASE_QCOW2=basic-debian-10.12.0-vm.qcow2
AUTO_INSTALL_PRESEED=debian-10-autoinstall-preseed.seed
ISO_CREATED_MARKER=iso/README.txt

INITIAL_DISK_SIZE=20G
KVM_CORES=2
KVM_INSTALL_RAM=1G
KVM_RAM=8G

SSH_MAX_INIT_SECONDS=60
DELAY=0.1
RETRIES=$(shell echo "$(SSH_MAX_INIT_SECONDS)/$(DELAY)" | bc)

default: launch-base-vm

clean:
	rm -rf iso *-autoinstall.iso *.qcow2 *.port *.pid *.qcow2.sh

spotless:
	git clean -dffx
	git submodule foreach --recursive git clean -dffx


# download the base install image
$(DISTRO_ORIG_ISO):
	@echo "begin $@"
	wget $(DISTRO_ISO_URL) --output-document=$@
	ls -l $@
	@echo "SUCCESS $@"

# extract the contents of the image
$(ISO_CREATED_MARKER): $(DISTRO_ORIG_ISO)
	mkdir -pv iso
	cd iso && 7z x ../$<
	echo "updating timestamp so make(1) knows when this was extracted"
	touch $@

vm_root_password:
	@echo "begin $@"
	touch vm_root_password
	chmod -v 600 vm_root_password
	cat /dev/urandom \
		| tr --delete --complement 'a-zA-Z0-9' \
		| fold --width=32 \
		| head --lines=1 \
		> vm_root_password
	ls -l vm_root_password
	@echo "SUCCESS $@"

SSH_PARAMS="-i ./id_rsa_tmp -oNoHostAuthenticationForLocalhost=yes"

id_rsa_tmp:
	@echo "begin $@"
	ssh-keygen -b 4096 -t rsa -N "" -C "temporary-key" -f ./id_rsa_tmp
	ls -l id_rsa_tmp
	@echo "SUCCESS $@"

id_rsa_tmp.pub: id_rsa_tmp
	@echo "begin $@"
	ls -l id_rsa_tmp.pub
	@echo "SUCCESS $@"

id_rsa_host_tmp:
	@echo "begin $@"
	ssh-keygen -b 4096 -t rsa -N "" -C "temp-host-key" -f ./id_rsa_host_tmp
	ls -l id_rsa_host_tmp
	@echo "SUCCESS $@"

id_rsa_host_tmp.pub: id_rsa_host_tmp
	@echo "begin $@"
	ls -l id_rsa_host_tmp.pub
	@echo "SUCCESS $@"

iso/authorized_keys: $(ISO_CREATED_MARKER) id_rsa_tmp.pub \
		id_rsa_host_tmp.pub id_rsa_host_tmp
	@echo "begin $@"
	cp -v ./id_rsa_tmp.pub		iso/authorized_keys
	cp -v ./id_rsa_host_tmp.pub	iso/id_rsa_host_tmp.pub
	cp -v ./id_rsa_host_tmp		iso/id_rsa_host_tmp
	@echo "SUCCESS $@"

# copy the preseed file to the appropriate location
# CONSIDER: using sed to replace items or m4 to expand macros
# CONSIDER: could add encryption to preseed file if we decide we need it
iso/preseed/autoinstall-preseed.seed: $(AUTO_INSTALL_PRESEED) \
		$(ISO_CREATED_MARKER)
	mkdir -pv iso/preseed
	cp -v $< $@

# update the grub.cfg to do a preseeded install
# (Used for Legacy BIOS)
iso/isolinux/isolinux.cfg : isolinux.cfg $(ISO_CREATED_MARKER)
	cp -v $< $@

# generate the new iso install image
$(ISO_TARGET): iso/preseed/autoinstall-preseed.seed \
		iso/isolinux/isolinux.cfg \
		iso/authorized_keys
	@echo "begin $@"
	genisoimage -o $@ -b isolinux/isolinux.bin -c isolinux/boot.cat \
		-no-emul-boot -boot-load-size 4 -boot-info-table -J -R \
		-V "$(ISO_TARGET_VOLUME)" iso
	ls -l $(ISO_TARGET)
	@echo "SUCCESS $@"

$(BASE_QCOW2): $(ISO_TARGET)
	@echo "begin $@"
	qemu-img create -f qcow2 tmp.qcow2 $(INITIAL_DISK_SIZE)
	qemu-system-x86_64 -hda tmp.qcow2 -cdrom $(ISO_TARGET) \
		-m $(KVM_INSTALL_RAM) -smp $(KVM_CORES) \
		-machine type=pc,accel=kvm \
		-display none
	mv -v tmp.qcow2 $(BASE_QCOW2)
	ls -l $(BASE_QCOW2)
	@echo "SUCCESS $@"

launch-base-vm: $(BASE_QCOW2)
	@echo "begin $@"
	KVM_RAM=$(KVM_RAM) KVM_CORES=$(KVM_CORES) KVM_SSH_PARAMS=$(SSH_PARAMS) \
		bin/launch-qemu $(BASE_QCOW2)
	bin/retry $(RETRIES) $(DELAY) \
		./$(BASE_QCOW2).ssh.sh '/bin/true'
	echo "check the key matches the one we generated"
	ssh-keyscan -p`cat $(BASE_QCOW2).ssh.port` 127.0.0.1 \
		| grep `cat id_rsa_host_tmp.pub | cut -f2 -d' '`
	./basic-debian-10.12.0-vm.qcow2.ssh.sh '/bin/true'
	@echo "SUCCESS $@"

shutdown-kvm:
	@echo "begin $@"
	./$(BASE_QCOW2).ssh.sh 'shutdown -h -t 2 now & exit'
	{ while kill -0 `cat $(BASE_QCOW2).pid`; do \
		echo "wating for `cat $(BASE_QCOW2).pid`"; sleep 1; done }
	sleep 1
	echo "yay"
