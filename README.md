# HTPlay-1 development repository

Isolated development copy of the HTPlay-1 addon source, based on production
source version 2.0.71. This repository is not the production catalog.

## Safety boundary
- No GitHub Release publishing or production catalog update workflow is included.
- Do not merge into `htp1_sound`, publish a release, or install on an HTP-1
  without explicit approval.
- Do not change Shairport Sync configuration, playback, discovery, or timing
  behavior while developing the control interface.
- Build outputs are to remain CI artifacts for inspection until validated.

The production release workflows and production `index.json` were intentionally
excluded from this development snapshot.
