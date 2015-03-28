#!/bin/bash
set -e

# Change your to your user if this is a unique new image.
USER="redock"
BUILD="$USER/tiny-arch"
# Dependencies
function check () {
	hash $1 &>/dev/null || {
			echo "Could not find $1."
			exit 1
	}
}

check gpg
check docker
check curl
check tar
check xz

mkdir -p img
cd img

# Pull Pierre Schmitz PGP Key.
# http://pgp.mit.edu:11371/pks/lookup?op=vindex&fingerprint=on&exact=on&search=0x4AA4767BBC9C4B1D18AE28B77F2D434B9741E8AC
gpg --keyserver pgp.mit.edu --recv-keys 9741E8AC

#########################################
# Pull the Pacman image from kernel.org #
#########################################
VERSION=$(curl https://mirrors.kernel.org/archlinux/iso/latest/ | grep -Poh '(?<=archlinux-bootstrap-)\d*\.\d*\.\d*(?=\-x86_64)' | head -n 1)
curl -O https://mirrors.kernel.org/archlinux/iso/latest/archlinux-bootstrap-$VERSION-x86_64.tar.gz.sig

if  [[ -e "archlinux-bootstrap-$VERSION-x86_64.tar.gz" ]];  then
  gpg archlinux-bootstrap-$VERSION-x86_64.tar.gz.sig
else
  curl -O https://mirrors.kernel.org/archlinux/iso/latest/archlinux-bootstrap-$VERSION-x86_64.tar.gz
  gpg archlinux-bootstrap-$VERSION-x86_64.tar.gz.sig
fi

sudo rm -rf root.x86_64
tar xf archlinux-bootstrap-$VERSION-x86_64.tar.gz > /dev/null

#####################################
# Update and clean the pulled image #
#####################################
sudo ./root.x86_64/bin/arch-chroot root.x86_64 << EOF
    echo 'Server = https://mirrors.kernel.org/archlinux/\$repo/os/\$arch' > /etc/pacman.d/mirrorlist
    pacman-key --init
    pacman-key --populate archlinux
    pacman -Rc --noconfirm arch-install-scripts dbus glib2 hwids kbd kmod libdbus libseccomp libsystemd lz4 shadow systemd util-linux
    pacman -Syu --noconfirm
    pacman -Scc --noconfirm
    rm /var/cache/pacman/pkg/*
    rm -rf /usr/share/man /usr/share/info /usr/share/doc /usr/share/locale README
    exit
EOF

sudo chown -R root:root root.x86_64

###
# udev doesnt work in containers, rebuild /dev
# Taken from https://raw.githubusercontent.com/dotcloud/docker/master/contrib/mkimage-arch.sh
###
DEV=root.x86_64/dev
sudo bash << EOF
    rm -rf $DEV
    mkdir -p $DEV
    mknod -m 666 $DEV/null c 1 3
    mknod -m 666 $DEV/zero c 1 5
    mknod -m 666 $DEV/random c 1 8
    mknod -m 666 $DEV/urandom c 1 9
    mkdir -m 755 $DEV/pts
    mkdir -m 1777 $DEV/shm
    mknod -m 666 $DEV/tty c 5 0
    mknod -m 600 $DEV/console c 5 1
    mknod -m 666 $DEV/tty0 c 4 0
    mknod -m 666 $DEV/full c 1 7
    mknod -m 600 $DEV/initctl p
    mknod -m 666 $DEV/ptmx c 5 2
    ln -sf /proc/self/fd $DEV/fd
EOF

######################
# Create the tarball #
######################
sudo tar cvfJ root.x86_64.tar.xz -C root.x86_64 .
#TODO: compression progress instead of verbose
#sudo su << EOF 
#  tar cf -C root.x86_64 . | pv -s `du -sb . | grep -o '[0-9]\+'` -N tar  | xz > root.x86_64.tar.xz
#EOF
