{
  image,
  healthCheck,
  activation ? { },
  storage ? { },
  runner ? { },
  pinRefresh ? { },
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
    pinRefresh
    description
    ;
}
// (if localFlakeAttribute == null then { } else { inherit localFlakeAttribute; })
