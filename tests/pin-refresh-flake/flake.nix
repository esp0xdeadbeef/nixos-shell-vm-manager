{
  outputs =
    { self }:
    {
      packages.x86_64-linux.refresh-vm = ./image;
    };
}
