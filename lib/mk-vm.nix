{
  image,
  healthCheck,
  activation ? { },
  storage ? { },
  runner ? { },
  description ? "nixos-shell VM",
  localFlakeAttribute ? null,
}:
{
  inherit
    image
    healthCheck
    activation
    storage
    runner
    description
    ;
}
// (if localFlakeAttribute == null then { } else { inherit localFlakeAttribute; })
