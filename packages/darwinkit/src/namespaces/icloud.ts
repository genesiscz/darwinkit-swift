import type { DarwinKitClient } from "../client.js"
import type {
  MethodMap,
  MethodName,
  PreparedCall,
  ICloudStatusResult,
  ICloudReadParams,
  ICloudReadResult,
  ICloudWriteParams,
  ICloudWriteBytesParams,
  ICloudDeleteParams,
  ICloudMoveParams,
  ICloudCopyFileParams,
  ICloudListDirParams,
  ICloudListDirResult,
  ICloudEnsureDirParams,
  ICloudOkResult,
  FilesChangedNotification,
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

export class ICloud {
  private client: DarwinKitClient
  private filesChangedListeners: Array<
    (notification: FilesChangedNotification) => void
  > = []

  readonly read: {
    (
      params: ICloudReadParams,
      options?: { timeout?: number },
    ): Promise<ICloudReadResult>
    prepare(params: ICloudReadParams): PreparedCall<"icloud.read">
  }
  readonly write: {
    (
      params: ICloudWriteParams,
      options?: { timeout?: number },
    ): Promise<ICloudOkResult>
    prepare(params: ICloudWriteParams): PreparedCall<"icloud.write">
  }
  readonly writeBytes: {
    (
      params: ICloudWriteBytesParams,
      options?: { timeout?: number },
    ): Promise<ICloudOkResult>
    prepare(params: ICloudWriteBytesParams): PreparedCall<"icloud.write_bytes">
  }
  readonly delete: {
    (
      params: ICloudDeleteParams,
      options?: { timeout?: number },
    ): Promise<ICloudOkResult>
    prepare(params: ICloudDeleteParams): PreparedCall<"icloud.delete">
  }
  readonly move: {
    (
      params: ICloudMoveParams,
      options?: { timeout?: number },
    ): Promise<ICloudOkResult>
    prepare(params: ICloudMoveParams): PreparedCall<"icloud.move">
  }
  readonly copyFile: {
    (
      params: ICloudCopyFileParams,
      options?: { timeout?: number },
    ): Promise<ICloudOkResult>
    prepare(params: ICloudCopyFileParams): PreparedCall<"icloud.copy_file">
  }
  readonly listDir: {
    (
      params: ICloudListDirParams,
      options?: { timeout?: number },
    ): Promise<ICloudListDirResult>
    prepare(params: ICloudListDirParams): PreparedCall<"icloud.list_dir">
  }
  readonly ensureDir: {
    (
      params: ICloudEnsureDirParams,
      options?: { timeout?: number },
    ): Promise<ICloudOkResult>
    prepare(params: ICloudEnsureDirParams): PreparedCall<"icloud.ensure_dir">
  }

  constructor(client: DarwinKitClient) {
    this.client = client
    this.read = method(client, "icloud.read") as ICloud["read"]
    this.write = method(client, "icloud.write") as ICloud["write"]
    this.writeBytes = method(
      client,
      "icloud.write_bytes",
    ) as ICloud["writeBytes"]
    this.delete = method(client, "icloud.delete") as ICloud["delete"]
    this.move = method(client, "icloud.move") as ICloud["move"]
    this.copyFile = method(client, "icloud.copy_file") as ICloud["copyFile"]
    this.listDir = method(client, "icloud.list_dir") as ICloud["listDir"]
    this.ensureDir = method(client, "icloud.ensure_dir") as ICloud["ensureDir"]
  }

  status(options?: { timeout?: number }): Promise<ICloudStatusResult> {
    return this.client.call(
      "icloud.status",
      {} as Record<string, never>,
      options,
    )
  }

  startMonitoring(options?: { timeout?: number }): Promise<ICloudOkResult> {
    return this.client.call(
      "icloud.start_monitoring",
      {} as Record<string, never>,
      options,
    )
  }

  stopMonitoring(options?: { timeout?: number }): Promise<ICloudOkResult> {
    return this.client.call(
      "icloud.stop_monitoring",
      {} as Record<string, never>,
      options,
    )
  }

  onFilesChanged(
    handler: (notification: FilesChangedNotification) => void,
  ): () => void {
    this.filesChangedListeners.push(handler)
    return () => {
      const idx = this.filesChangedListeners.indexOf(handler)
      if (idx !== -1) this.filesChangedListeners.splice(idx, 1)
    }
  }

  /** @internal Called by DarwinKit client when filesChanged notification arrives */
  _notifyFilesChanged(notification: FilesChangedNotification): void {
    for (const handler of this.filesChangedListeners) {
      handler(notification)
    }
  }
}
