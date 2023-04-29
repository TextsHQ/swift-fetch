import type { FetchResponse } from '@textshq/platform-sdk'

interface SwiftFetchRequestOptions {
  method?: string
  headers?: Record<string, string>
  body?: Buffer
}

// eslint-disable-next-line global-require
const SwiftFetch = require('../build/SwiftFetch.node') as {
  request(url: string, options?: SwiftFetchRequestOptions): Promise<FetchResponse<Buffer>>
}

export const { request } = SwiftFetch
