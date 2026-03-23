import type { DarwinKitClient } from "../client.js";
import type {
  MethodMap,
  MethodName,
  PreparedCall,
  OCRParams,
  OCRResult,
  ClassifyParams,
  ClassifyResult,
  FeaturePrintParams,
  FeaturePrintResult,
  SimilarityParams,
  SimilarityResult,
  DetectFacesParams,
  DetectFacesResult,
  DetectBarcodesParams,
  DetectBarcodesResult,
  SaliencyParams,
  SaliencyResultData,
} from "../types.js";

// helper to create callable+preparable methods
type PreparedMethod<M extends MethodName> = ((
  params: MethodMap[M]["params"],
  options?: { timeout?: number },
) => Promise<MethodMap[M]["result"]>) & {
  prepare(params: MethodMap[M]["params"]): PreparedCall<M>;
};

function method<M extends MethodName>(
  client: DarwinKitClient,
  name: M,
): PreparedMethod<M> {
  const fn = ((
    params: MethodMap[M]["params"],
    options?: { timeout?: number },
  ) => client.call(name, params, options)) as PreparedMethod<M>;
  fn.prepare = (params: MethodMap[M]["params"]): PreparedCall<M> => ({
    method: name,
    params,
    __brand: undefined as unknown as MethodMap[M]["result"],
  });
  return fn;
}

export class Vision {
  readonly ocr: {
    (params: OCRParams, options?: { timeout?: number }): Promise<OCRResult>;
    prepare(params: OCRParams): PreparedCall<"vision.ocr">;
  };

  readonly classify: {
    (
      params: ClassifyParams,
      options?: { timeout?: number },
    ): Promise<ClassifyResult>;
    prepare(params: ClassifyParams): PreparedCall<"vision.classify">;
  };

  readonly featurePrint: {
    (
      params: FeaturePrintParams,
      options?: { timeout?: number },
    ): Promise<FeaturePrintResult>;
    prepare(params: FeaturePrintParams): PreparedCall<"vision.feature_print">;
  };

  readonly similarity: {
    (
      params: SimilarityParams,
      options?: { timeout?: number },
    ): Promise<SimilarityResult>;
    prepare(params: SimilarityParams): PreparedCall<"vision.similarity">;
  };

  readonly detectFaces: {
    (
      params: DetectFacesParams,
      options?: { timeout?: number },
    ): Promise<DetectFacesResult>;
    prepare(params: DetectFacesParams): PreparedCall<"vision.detect_faces">;
  };

  readonly detectBarcodes: {
    (
      params: DetectBarcodesParams,
      options?: { timeout?: number },
    ): Promise<DetectBarcodesResult>;
    prepare(
      params: DetectBarcodesParams,
    ): PreparedCall<"vision.detect_barcodes">;
  };

  readonly saliency: {
    (
      params: SaliencyParams,
      options?: { timeout?: number },
    ): Promise<SaliencyResultData>;
    prepare(params: SaliencyParams): PreparedCall<"vision.saliency">;
  };

  constructor(client: DarwinKitClient) {
    this.ocr = method(client, "vision.ocr") as Vision["ocr"];
    this.classify = method(client, "vision.classify") as Vision["classify"];
    this.featurePrint = method(
      client,
      "vision.feature_print",
    ) as Vision["featurePrint"];
    this.similarity = method(
      client,
      "vision.similarity",
    ) as Vision["similarity"];
    this.detectFaces = method(
      client,
      "vision.detect_faces",
    ) as Vision["detectFaces"];
    this.detectBarcodes = method(
      client,
      "vision.detect_barcodes",
    ) as Vision["detectBarcodes"];
    this.saliency = method(client, "vision.saliency") as Vision["saliency"];
  }
}
