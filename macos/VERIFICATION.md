# Verification — SketchGlide 0.2.0 Test

Release checks are recorded in the sibling release QA directory. Build completion, an actual runtime check and physical input tests are separate evidence.

The release is ad hoc signed and unnotarized. No Developer ID signing, notarization, payment, paid cloud request or private drawing is needed for local checks.

Relevant checks include a clean native release build; exact metadata and bundled model/resources; an isolated shipping-entry-point launch; native screenshots of an empty home and a synthetic drawing; export and model inference; extracted ZIP and mounted DMG signature validation; source/package hygiene. Native production-source executable harnesses check geometry, storage, input handling, cache output, mathematics, export, AI routing with mocks and 3D codecs.

The installed Command Line Tools cannot import XCTest. The XCTest suite is supplied for a compatible full Xcode environment; it must not be reported as executed here. Physical tablets, remote labels, live paid cloud AI, Intel Macs, older macOS, future bugs, fixed 120 FPS and battery/thermal performance are not established by synthetic checks.
