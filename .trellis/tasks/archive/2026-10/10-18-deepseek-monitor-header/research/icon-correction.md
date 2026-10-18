# DeepSeek icon correction

The user rejected the initial generic whale and supplied the actual DeepSeek mark. The shared `DeepSeekProviderIcon` must match that reference on Home, Usage, and Settings.

Retrieved the original mark on 2026-10-18 from [DeepSeek's official home page](https://www.deepseek.com/). The header wordmark SVG has viewBox `0 0 143 23`; the tenth path (index 9) is the whale, within a clipping rectangle x=0.163086, y=1.75, width=26.634, height=19.6. The original path uses absolute M/C/V/Z operations and the default nonzero fill rule. Its shape contains the actual negative-space belly and eye detail.

The extracted mark is saved verbatim as `deepseek-official-mark.svg` beside this note, with a tight matching viewBox and the reference blue `#4D6BFE`. Preserve exact geometry and aspect ratio when converting to native SwiftUI Path. Do not edit the user's raster reference, draw a new approximation, or add an SVG parsing dependency. Include concise source attribution in third-party notices.

Validate with a standalone enlarged icon render plus existing Aqua/Dark Aqua Home/Usage/Settings render tests. Header frames should retain their existing dimensions. No new network/credential behavior is requested.
