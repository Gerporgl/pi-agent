#!/bin/bash


# Run a base systemd-container

# This is mostly an example on how to run the container locally
# setting the root password at run time here is for convenience 
# for testing, without baking in the root password in the image itself
# By default, if not set, the root password is not set, and there is no way to access anything
# This is the default secure behavior
CONTAINER_NAME=pi-agent
if [ ! $IMAGE_NAME ]; then
    IMAGE_NAME=ghcr.io/gerporgl/pi-agent:latest
fi


podman=$(podman -v 2>/dev/null | grep -c -i podman)
if [ "$podman" == "1" ]; then
    # Keeps the host user id the same inside the container for the mounted file system.
    # There are other ways of doing this; it is optional.
	opts="--userns=keep-id"
	command=podman
	echo "You have podman installed"
    podman rm -fi $CONTAINER_NAME
else
    opts=" --tmpfs /run
            --tmpfs /run/lock
            --tmpfs /tmp
            --tmpfs /run/dbus
            --security-opt systempaths=unconfined
            --security-opt label=disable
            --cgroupns host
            -v /sys/fs/cgroup:/sys/fs/cgroup:rw "
    command=docker
    echo "You are NOT using podman... some permissions adjustments were needed for Docker. Podman or LXC is recommended instead."
    docker rm -f $CONTAINER_NAME
fi

echo "============================================================================"
echo "You have to set a root password first"
echo "Once the container starts afterward and you are prompted for the login,"
echo "use root and your new password. If you set an empty password this will also work..."
echo "To stop the container and delete it, just use the poweroff command when inside the container"
echo "or stop the container with docker stop externally in a separate terminal"
echo "============================================================================"

read -s -p "Enter the desired root password: " root_password && echo ""
echo "Ok"

$command create --rm -it \
    -p 0.0.0.0:8555:8504 \
    -p 0.0.0.0:2222:22 \
    $opts \
    -v `pwd`/home-data:/home/ubuntu \
    --name $CONTAINER_NAME \
    $IMAGE_NAME

echo "Container created"

tmpfile=$(mktemp)
tmpfile_out=$(mktemp)
$command cp $CONTAINER_NAME:/etc/shadow $tmpfile
echo "Copied current password file"
awk -v password=$(echo $root_password | openssl passwd -1 -stdin) \
      'BEGIN{FS=OFS=":"} $1=="root" {$2=password}1' $tmpfile > $tmpfile_out
# Optionally install your ssh public key for root access
if [ -f ~/.ssh/id_ed25519.pub ]; then
    $command cp ~/.ssh/id_ed25519.pub $CONTAINER_NAME:/root/.ssh/authorized_keys
    echo "Copied ssh public key"
fi
$command cp $tmpfile_out $CONTAINER_NAME:/etc/shadow
echo "Copied new password"
rm $tmpfile && rm $tmpfile_out
echo "Password was set"

$command start $CONTAINER_NAME
echo "Container started"
echo "Attaching..."
$command attach $CONTAINER_NAME
