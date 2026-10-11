# Offline maths symbol recognition resources

The public DeTeXt model recognizes individual handwritten symbols. It does not recognize complete equations, and candidates require user review.

Model author: Venkata S Govindarajan (Venkat). Model version: 0.95. The model's embedded metadata explicitly declares the MIT License. Retain the accompanying MIT notices.

Public sources:

- DeTeXt: https://github.com/venkatasg/DeTeXt
- DeTeXt supplementary model/training code: https://github.com/venkatasg/DeTeXt-Supplementary
- Developer documentation: https://venkatasg.net/apps/detext

Pinned source commits:

- DeTeXt: b36e77f7da3987bcfc6b383e494af84166c30c2b
- Supplementary: df088afc40abe8aee66928b828586594d0f14eaa

`deTeX.mlmodel` is the unmodified public `Resources/deTeX.mlmodel` from the DeTeXt source repository. It is identical to the supplementary repository model. SHA-256: `55f02315b2d058f90c6c5db682fc106563a0cac697e99547758d0f8f86de19d5`. Size: 14,694,160 bytes.

`symbols.json` is derived from the public DeTeXt `Resources/symbols.json`, retaining only ID, LaTeX command, and optional package for each of its 1,098 records. No upstream Unicode translation table, generated SVG assets, app icon, or branding is included. The native glyph mapping in SketchGlide is independently maintained.

Training-data provenance: the model developer trained it on the Detexify sample database. Detexify data is available under the Open Database License (ODbL) 1.0; it must not be described as MIT licensed. SketchGlide includes the developer's published MIT model, rather than the training database. No training database is bundled or modified.

Contains information from Detexify's sample data, available at https://github.com/kirel/detexify-data under the Open Database License: https://opendatacommons.org/licenses/odbl/1-0/

Inference runs locally through Apple Core ML. No drawing, prompt, or result is sent to a server by the symbol recognizer.
