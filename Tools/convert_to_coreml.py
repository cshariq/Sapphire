#!/usr/bin/env python3
"""
Template script to convert a PyTorch model to Core ML using coremltools.

Edit the `model_path`, `input_shape`, and `output_path` vintelligencebles as needed.

Requires:
- python3
- pip install coremltools torch torchvision

Usage:
  python convert_to_coreml.py
"""
import coremltools as ct
import torch

# === User editable ===
model_path = "model.pt"  # Path to a PyTorch .pt or .pth (scripted or state_dict + loader)
input_shape = (1, 3, 112, 112)
output_path = "ModernFace.mlpackage"
use_mlprogram = True
quantize_fp16 = True
# ======================


def load_torch_model(path):
    # If model is a scripted/traced module, you can load directly.
    return torch.jit.load(path)


def main():
    print("Loading PyTorch model...")
    model = load_torch_model(model_path)
    model.eval()

    print("Tracing and converting to Core ML...")
    example_input = torch.randn(input_shape)
    traced = torch.jit.trace(model, example_input)

    mlmodel = ct.convert(traced, inputs=[ct.TensorType(shape=input_shape, name='input')], convert_to='mlprogram' if use_mlprogram else None)

    if quantize_fp16:
        spec = mlmodel.get_spec()
        spec_fp16 = ct.models.neural_network.quantization_utils.convert_neural_network_spec_weights_to_fp16(spec)
        mlmodel = ct.models.MLModel(spec_fp16)

    print(f"Saving to {output_path}...")
    mlmodel.save(output_path)
    print("Done.")


if __name__ == '__main__':
    main()
