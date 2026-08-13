"""
Strips the TFLite_Detection_PostProcess custom op from an SSD .tflite model
and re-points the subgraph's outputs at that op's 3 input tensors (raw
box_encodings, class_predictions, anchors) instead, so the model can run on
an interpreter that doesn't have the custom op registered - the caller does
box-decode + NMS itself using the same math the custom op would have used.

Why: TensorFlowLiteC (the iOS TFLite runtime this app's Flutter plugin uses,
see third_party/flutter_tflite) ships this op's kernel compiled in but never
registers it in the interpreter's default resolver, and its C++ symbol isn't
exported for external linking either - so on iOS, Interpreter::Invoke() just
fails (kTfLiteError) for any model built with add_postprocessing_op=True
(the standard way to export an SSD detector for TFLite). Re-training/
re-exporting without that flag is the "real" fix if you still have the
training checkpoint; this is the workaround for when you don't.

Regenerate assets/*_raw.tflite with this whenever the corresponding
assets/*.tflite source model changes. The raw-tensor consumer is
lib/ssd_postprocess.dart; the native passthrough is
third_party/flutter_tflite/ios/Classes/TflitePlugin.mm's
dumpRawSSDOutputs/detectObjectRawOn{Image,Frame}.

Requires `tensorflow` (for its bundled tflite schema module with object-API
support - the standalone `tflite` pip package doesn't have it) and
`flatbuffers`: pip install tensorflow flatbuffers

Usage: python strip_postprocess.py input.tflite output.tflite
"""
import sys
import flatbuffers
from tensorflow.lite.python.schema_py_generated import ModelT

path_in = sys.argv[1]
path_out = sys.argv[2]

with open(path_in, 'rb') as f:
    buf = bytearray(f.read())

model_t = ModelT.InitFromPackedBuf(buf, 0)
subgraph = model_t.subgraphs[0]

# Find the TFLite_Detection_PostProcess operator (assumed to be the only one).
opcodes = model_t.operatorCodes
target_op_index = None
for i, op in enumerate(subgraph.operators):
    opcode = opcodes[op.opcodeIndex]
    if opcode.customCode and opcode.customCode.decode('utf-8') == 'TFLite_Detection_PostProcess':
        target_op_index = i
        break

if target_op_index is None:
    print("No TFLite_Detection_PostProcess op found - nothing to do.")
    sys.exit(1)

target_op = subgraph.operators[target_op_index]
raw_inputs = list(target_op.inputs)  # [box_encodings, class_predictions, anchors]
print(f"Found custom op at operator index {target_op_index}, inputs={raw_inputs}")

for idx in raw_inputs:
    t = subgraph.tensors[idx]
    print(f"  tensor#{idx} name={t.name} shape={list(t.shape) if t.shape is not None else None} type={t.type}")

# Drop the custom op node entirely and repoint the subgraph outputs at its
# raw inputs (in that fixed order: box_encodings, class_predictions, anchors -
# lib/ssd_postprocess.dart relies on this exact order).
del subgraph.operators[target_op_index]
subgraph.outputs = raw_inputs

builder = flatbuffers.Builder(0)
root = model_t.Pack(builder)
builder.Finish(root, file_identifier=b'TFL3')
out_buf = builder.Output()

with open(path_out, 'wb') as f:
    f.write(out_buf)

print(f"Wrote {path_out} ({len(out_buf)} bytes)")
