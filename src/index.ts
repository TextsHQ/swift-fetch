import type { FetchOptions, FetchResponse } from '@textshq/platform-sdk'
import FormData from 'form-data'

interface SwiftFetchRequestOptions {
  method?: string
  headers?: Record<string, string>
  body?: Buffer
}

// eslint-disable-next-line global-require
const SwiftFetch = require('../build/SwiftFetch.node') as {
  request(url: string, options?: SwiftFetchRequestOptions): Promise<FetchResponse<Buffer>>
}

export async function fetch(url: string, options?: FetchOptions): Promise<FetchResponse<Buffer>> {
  let urlString = url
  const swiftOptions: SwiftFetchRequestOptions = {
    method: options?.method,
    headers: options?.headers,
  }

  if (options?.cookieJar) {
    swiftOptions.headers = {
      ...swiftOptions.headers,
      Cookie: options.cookieJar.getCookieStringSync(url),
    }
  }

  if (options?.body?.constructor.name === 'FormData') {
    swiftOptions.headers = (options.body as FormData).getHeaders(swiftOptions.headers)
    swiftOptions.body = (options.body as FormData).getBuffer()
  }

  if (options?.form) {
    const formData = new FormData()

    for (const [key, value] of Object.entries(options.form)) {
      formData.append(key, value)
    }

    swiftOptions.headers = formData.getHeaders(swiftOptions.headers)
    swiftOptions.body = formData.getBuffer()
  }

  if (options?.searchParams) {
    const searchParams = new URLSearchParams(options.searchParams as Record<string, string>)
    urlString += `?${searchParams.toString()}`
  }

  const response = await SwiftFetch.request(urlString, swiftOptions)

  if (response.headers.cookie) {
    options?.cookieJar?.setCookieSync(response.headers.cookie, url)
  }

  return response
}
