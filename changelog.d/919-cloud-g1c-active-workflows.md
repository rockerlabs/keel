- `tools/cloud-brief.sh` G1c now counts only workflows whose `state` is `active` (dir #919). A repository whose only
  workflow is disabled is refused before any credit is spent instead of being dispatched and then never landing;
  `docs/cloud.md`'s G1c row says "active" and `tests/test_cloud_doc.sh` pins it.
