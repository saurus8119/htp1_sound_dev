# AirPlay ARM build

Builds Shairport Sync 5.6.1 and NQPTP 1.2.9 for ARMv7 in a Debian 9 / glibc 2.24 userspace. These releases use Shared Memory Interface 11 (SMI11), and the build fails unless both binaries report `smi11`. Shairport Sync 5.6.1 uses the FFmpeg ALAC decoder for AirPlay 2.

The target runtime is the HTP-1 firmware, not the Docker image. The build checks architecture, dynamic dependencies and version/interface strings, but it cannot prove that all runtime libraries exist on a given firmware or that audio playback works on physical hardware.
