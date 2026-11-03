# AirPlay add-on update: 0.1.1

- Shairport Sync source pinned to 5.6.1.
- NQPTP source pinned to 1.2.9; both programs must report SMI11.
- Build fails if either binary reports an incompatible shared-memory interface.
- Fixed build script to run autoreconf/configure in the Shairport Sync source tree (not the NQPTP tree).
- Added explicit FFmpeg, libdaemon, soxr, and libplist build dependencies needed by the current Shairport Sync build.
- Kept the HTP-1 add-on runtime package separate from diagnostics; the release asset is the .tar.gz, not the Actions ZIP.

Validation performed here: shell syntax, JSON syntax, source version pins, SMI11 guard checks, and archive layout scripts. The ARM build and physical HTP-1 playback have not been run in this environment; CI must complete the actual build before release.
