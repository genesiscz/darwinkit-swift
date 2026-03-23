export const ErrorCodes = {
  PARSE_ERROR: -32700,
  INVALID_REQUEST: -32600,
  METHOD_NOT_FOUND: -32601,
  INVALID_PARAMS: -32602,
  INTERNAL_ERROR: -32603,
  FRAMEWORK_UNAVAILABLE: -32001,
  PERMISSION_DENIED: -32002,
  OS_VERSION_TOO_OLD: -32003,
  OPERATION_CANCELLED: -32004,
} as const;

export type ErrorCode = (typeof ErrorCodes)[keyof typeof ErrorCodes];

export class DarwinKitError extends Error {
  override readonly name = "DarwinKitError";
  constructor(
    public readonly code: number,
    message: string,
    public readonly data?: unknown,
  ) {
    super(message);
  }
  get isFrameworkUnavailable() {
    return this.code === ErrorCodes.FRAMEWORK_UNAVAILABLE;
  }
  get isPermissionDenied() {
    return this.code === ErrorCodes.PERMISSION_DENIED;
  }
  get isOSVersionTooOld() {
    return this.code === ErrorCodes.OS_VERSION_TOO_OLD;
  }
  get isCancelled() {
    return this.code === ErrorCodes.OPERATION_CANCELLED;
  }
}
