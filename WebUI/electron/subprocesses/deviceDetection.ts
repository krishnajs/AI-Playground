export function levelZeroDeviceSelectorEnv(id?: string): { ONEAPI_DEVICE_SELECTOR: string } {
  // Default to '*' (all Level-Zero devices visible) so the "Auto select device"
  // UI option keeps its original semantics on both Windows and Linux. Using '0'
  // here would silently restrict multi-tile / multi-GPU systems (e.g. Panther
  // Lake's 8 render tiles) to the first device only.
  return { ONEAPI_DEVICE_SELECTOR: `level_zero:${id ?? '*'}` }
}

/** Restrict PyTorch/CUDA to one GPU. Omit when id is auto (`*` or undefined) so all devices stay visible. */
export function cudaVisibleDevicesEnv(id?: string): Record<string, string> {
  if (id === undefined || id === '*') {
    return {}
  }
  return { CUDA_VISIBLE_DEVICES: id }
}

export function vulkanDeviceSelectorEnv(id?: string): { GGML_VK_VISIBLE_DEVICES: string } {
  return { GGML_VK_VISIBLE_DEVICES: id ?? '0' }
}

export function openVinoDeviceSelectorEnv(id?: string): { OPENVINO_DEVICE: string } {
  return { OPENVINO_DEVICE: id ?? 'AUTO' }
}
