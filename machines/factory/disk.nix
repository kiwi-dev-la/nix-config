# One virtual disk: a boot partition and the rest as the root filesystem.
{
  disko.devices.disk.main = {
    type = "disk";
    # vm/factory-vm.sh attaches the disk with this serial number.
    device = "/dev/disk/by-id/virtio-factory-root";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
