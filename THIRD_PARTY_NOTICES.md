# Third-party notices

Karim Ink includes the following public resources and adapted code. Their licences are separate from the licence applied to Karim Ink's own source.

## DeTeXt symbol recognition

Author: **Venkata S Govindarajan (Venkat)**.

- [DeTeXt source](https://github.com/venkatasg/DeTeXt), pinned source commit `b36e77f7da3987bcfc6b383e494af84166c30c2b`.
- [DeTeXt Supplementary](https://github.com/venkatasg/DeTeXt-Supplementary), pinned source commit `df088afc40abe8aee66928b828586594d0f14eaa`.
- [Developer information](https://venkatasg.net/apps/detext).

The bundled `deTeX.mlmodel` is the developer's unmodified public model, version 0.95, and its metadata declares the MIT License. The command catalogue retains the ID, LaTeX command and optional package from 1,098 public records. Recognition runs locally with Apple Core ML and operates on individual symbols.

Retained notices: [DeTeXt MIT licence](third-party-licenses/LICENSE-DeTeXt.txt), copyright © 2025 Venkat, and [Supplementary MIT licence](third-party-licenses/LICENSE-DeTeXt-Supplementary.txt), copyright © 2020 Venkat.

The original DeTeXt app, app icon, branding, generated SVG assets and Unicode translation table are not bundled. Karim Ink's board glyph mapping is independently maintained.

### Training-data attribution

The published model was trained by its developer on Detexify sample data. The training database is not bundled or modified by Karim Ink and must not be described as MIT licensed.

Contains information from Detexify's sample data, available at [kirel/detexify-data](https://github.com/kirel/detexify-data) under the [Open Database License 1.0](https://opendatacommons.org/licenses/odbl/1-0/).

## Optional Quick Keys community bridge

Some packet layouts in the optional native bridge are adapted from [node-xencelabs-quick-keys](https://github.com/Julusian/node-xencelabs-quick-keys) by **Julian Waller**, reviewed at commit `8cfbb9141c3b0df005a7f20f2bf090029d6a7948`.

Licence: MIT, copyright © 2021 Julian Waller. The complete notice is retained in [LICENSE-QuickKeys.txt](third-party-licenses/LICENSE-QuickKeys.txt).

This is a community protocol implementation. It is not a manufacturer SDK, driver replacement or vendor endorsement. Direct control is optional, disconnected by default and requires physical hardware testing.

## Names and teaching diagrams

Apple, OpenAI, Microsoft, Notion, Craft, Xencelabs, Wacom, Pearson and other referenced product names belong to their respective owners. Karim Ink is an independent project and does not claim their endorsement.

The searchable engineering library contains teaching drawings rendered by the app. It is not a certified reproduction of the IEC/ISO symbol databases. Check the diagram convention required by your course or project.
