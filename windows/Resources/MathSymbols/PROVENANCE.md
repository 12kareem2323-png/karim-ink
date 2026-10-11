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

`symbols.json` is derived from the public DeTeXt `Resources/symbols.json`, retaining only ID, LaTeX command, and optional package for each of its 1,098 records. No upstream Unicode translation table, generated SVG assets, app icon, or branding is included. The native glyph mapping in Engineering Board is independently maintained.

Training-data provenance: the model developer trained it on the Detexify sample database. Detexify data is available under the Open Database License (ODbL) 1.0; it must not be described as MIT licensed. Engineering Board includes the developer's published MIT model, rather than the training database. No training database is bundled or modified.

Contains information from Detexify's sample data, available at https://github.com/kirel/detexify-data under the Open Database License: https://opendatacommons.org/licenses/odbl/1-0/

The Windows app uses `deTeX.onnx`, converted from the above public Core ML file with unchanged trained weights and class order. ONNX SHA-256: `c8631ed08c684b1a37b35e764e262f6691356b0892feac04ab532876086ab4c4`. Input is raw 0–255 RGB float32 NCHW [1,3,200,300]; the original preprocessing scaler is part of the graph. `classes.json` records the original 1,098 class IDs in model order.

Inference runs locally through ONNX Runtime. No drawing, prompt, or result is sent to a server by the symbol recognizer. Seven synthetic fixture images were run through both the actual original Core ML CPU model and converted ONNX CPU model on macOS. All top class IDs matched; largest probability difference was 0.00000144. This checks conversion fidelity, not recognition accuracy or Windows runtime behaviour. The original conversion comparison predates this test release; this release’s current verification separately exercises the converted model in the packaged native Windows runtime.
