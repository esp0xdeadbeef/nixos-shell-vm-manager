# Requirements Traceability Matrix

Document: nixos-shell VM Manager RaTM
Status: Implemented; SMT, SIT, and authorized `s-tau` HAT evidence current

The controlled HAT outcome is recorded in `GAMP/HAT/README.md`. SAT remains
unauthorized and is not implied by any status in this matrix.

| FS | HDS | SDS | SMS | Planned verification |
| --- | --- | --- | --- | --- |
| FS-010 | FS-010-HDS-010 | FS-010-HDS-010-SDS-010 | FS-120-HDS-010-SDS-010-SMS-010 | closure/evaluation negative |
| FS-020 | FS-020-HDS-010 | FS-010-HDS-010-SDS-010 | FS-120-HDS-010-SDS-010-SMS-010 | offline runtime integration |
| FS-030 | FS-030-HDS-010 | FS-030-HDS-010-SDS-010 | FS-030-HDS-010-SDS-010-SMS-010 | immutable archive/lock negative |
| FS-040 | FS-040-HDS-010 | FS-040-HDS-010-SDS-010 | FS-040-HDS-010-SDS-010-SMS-010 | admission negative and slot test |
| FS-050 | FS-050-HDS-010 | FS-030-HDS-010-SDS-010 | FS-030-HDS-010-SDS-010-SMS-010 | running-process build isolation |
| FS-060 | FS-060-HDS-010 | FS-040-HDS-010-SDS-010 | FS-040-HDS-010-SDS-010-SMS-010 | provenance/precedence test |
| FS-070 | FS-070-HDS-010 | FS-070-HDS-010-SDS-010 | FS-070-HDS-010-SDS-010-SMS-010 | policy evaluation and jitter bounds |
| FS-075 | FS-075-HDS-010 | FS-075-HDS-010-SDS-010 | FS-075-HDS-010-SDS-010-SMS-010 | late-stop race and host-stop test |
| FS-080 | FS-080-HDS-010 | FS-080-HDS-010-SDS-010 | FS-070-HDS-010-SDS-010-SMS-010 | process plus functional negatives |
| FS-090 | FS-090-HDS-010 | FS-090-HDS-010-SDS-010 | FS-070-HDS-010-SDS-010-SMS-010 | successful and failed rollback |
| FS-100 | FS-100-HDS-010 | FS-100-HDS-010-SDS-010 | FS-070-HDS-010-SDS-010-SMS-010 | persistent marker preservation |
| FS-110 | FS-110-HDS-010 | FS-110-HDS-010-SDS-010 | FS-040-HDS-010-SDS-010-SMS-010 | lock/concurrency negatives |
| FS-120 | FS-120-HDS-010 | FS-120-HDS-010-SDS-010 | FS-120-HDS-010-SDS-010-SMS-010 | external consumer evaluation |
| FS-130 | FS-130-HDS-010 | FS-030-HDS-010-SDS-010 | FS-130-HDS-010-SDS-010-SMS-010 | CLI validation and live action |
| FS-140 | FS-140-HDS-010 | FS-140-HDS-010-SDS-010 | FS-140-HDS-010-SDS-010-SMS-010 | current SMT, SIT, authorized HAT |
| FS-150 | FS-150-HDS-010 | FS-150-HDS-010-SDS-010 | FS-150-HDS-010-SDS-010-SMS-010 | offline console input and stable-endpoint integration |
