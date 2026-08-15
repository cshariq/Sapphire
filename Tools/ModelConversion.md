Model conversion and integration notes
===================================

This document explains how to convert a PyTorch/ONNX/TensorFlow face model to Core ML
and the conventions this app expects for runtime compatibility with the generic loader.

Recommended models to evaluate:
- MobileFaceNet (fast, small)
- ResNet-50-based modern backbone (accurate)
- MagFace-small (balanced)

Conversion guidelines
---------------------
- Prefer Core ML Program (`mlpackage`) when possible (`convert_to='mlprogram'`) for better runtime performance.
- The runtime loader in `MLModelManager` expects the model to accept a single multi-array input
  and to produce a single multi-array output containing the embedding vector.

Input/Output Naming Convention
- Input: first input name will be used. For simplicity you can set the input tensor name to
  `input` during export.
- Output: the loader will take the first output returned by the model. Name the output
  `embeddings` or similar for clarity.

FP16 / INT8 Quantization
- Try fp16 first (lower accuracy impact):

  ```py
  import coremltools as ct
  mlmodel = ct.convert('model.pt', inputs=[ct.TensorType(shape=(1,3,112,112))], convert_to='mlprogram')
  spec = mlmodel.get_spec()
  fp16_spec = ct.models.neural_network.quantization_utils.convert_neural_network_spec_weights_to_fp16(spec)
  ct.models.MLModel(fp16_spec).save('ModernFace_fp16.mlpackage')
  ```

- If you need smaller size and are willing to test accuracy drop, try 8-bit linear quantization.

Validation
----------
After conversion validate numerically on a small set of inputs (compare PyTorch / TF output vs Core ML output)
to ensure there are no large numeric regressions.

Runtime notes
-------------
- Place the compiled `.mlmodelc` or `.mlpackage` inside the app bundle resources named `ModernFace`.
- The app will automatically load `ModernFace.mlmodelc` or `ModernFace.mlmodel` at runtime. This is the only supported model.

Example conversion scripts can be found in `convert_to_coreml.py` (template).
