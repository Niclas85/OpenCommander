# Zstandard decoder

Unmodified standalone decompressor generated from the official Zstandard
v1.5.7 tag, commit `f8745da6ff1ad1e7bab384bd1f9d742439278e99`:
https://github.com/facebook/zstd/tree/v1.5.7/build/single_file_libs

Generated with the upstream `create_single_file_decoder.sh`. Decoder SHA-256:
`5eb38abe0a7eea13674b312a006df72002d4192f0f0b4d09e6f03fb927a1f3d0`.
OpenCommander selects the BSD license, reproduced in `Zstandard-LICENSE.txt`
and included in the application resources. No compressor, CLI or legacy
pre-standard decoder is shipped. `ZstandardDecoder.c` provides the bounded
stream interface. Updates must regenerate from a pinned upstream release,
retain the license, and rerun the archive safety and native acceptance tests.
