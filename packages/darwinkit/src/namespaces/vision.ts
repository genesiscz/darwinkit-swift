import type { DarwinKitClient } from "../client.js"
import type {
  MethodMap,
  MethodName,
  PreparedCall,
  OCRParams,
  OCRResult,
} from "../types.js"

// helper to create callable+preparable methods
function method<M extends MethodName>(client: DarwinKitClient, name: M) {
  const fn = (
    params: MethodMap[M]["params"],
    options?: { timeout?: number },
  ) => client.call(name, params, options)
  fn.prepare = (params: MethodMap[M]["params"]): PreparedCall<M> => ({
    method: name,
    params,
    __brand: undefined as unknown as MethodMap[M]["result"],
  })
  return fn
}

export class Vision {
  readonly ocr: {
    (params: OCRParams, options?: { timeout?: number }): Promise<OCRResult>
    prepare(params: OCRParams): PreparedCall<"vision.ocr">
  }

  constructor(client: DarwinKitClient) {
    this.ocr = method(client, "vision.ocr") as Vision["ocr"]
  }
}
