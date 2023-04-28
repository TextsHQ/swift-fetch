import type { FetchResponse } from '@textshq/platform-sdk'

const SwiftFetch = require('../build/SwiftFetch.node') as {
  requestAsString(url: string): Promise<FetchResponse<string>>
  requestAsBuffer(url: string): Promise<FetchResponse<Buffer>>
}

export default {
  ...SwiftFetch,
}
