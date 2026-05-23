//
//  Marker.swift
//
//  Intentionally empty Swift file. Exists so the `CSherpaOnnxLink`
//  Swift target has at least one source, which is required by SPM
//  even for targets whose sole purpose is to carry `linkerSettings`
//  that propagate to consumers (in our case `-lc++` so the consumer's
//  link step pulls in the C++ standard library that sherpa-onnx's
//  static lib depends on).
//
//  Consumers do NOT need to `import CSherpaOnnxLink` for the linker
//  settings to take effect — being in the product's target list is
//  sufficient.
//

