import type { DarwinKitClient } from "../client.js"
import type {
  MethodMap,
  MethodName,
  PreparedCall,
  OCRParams,
  OCRResult,
} from "../types.js"

// helper to create callable+preparable methods
type PreparedMethod<M extends MethodName> = ((
  params: MethodMap[M]["params"],
  options?: { timeout?: number },
) => Promise<MethodMap[M]["result"]>) & {
  prepare(params: MethodMap[M]["params"]): PreparedCall<M>
}

function method<M extends MethodName>(
  client: DarwinKitClient,
  name: M,
): PreparedMethod<M> {
  const fn = ((
    params: MethodMap[M]["params"],
    options?: { timeout?: number },
  ) => client.call(name, params, options)) as PreparedMethod<M>
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
