import { Readable } from 'stream'
import type { FetchOptions, FetchResponse } from '@textshq/platform-sdk'
import FormData from 'form-data'

interface SwiftFetchRequestOptions {
  method?: string
  headers?: Record<string, string>
  body?: Buffer
}

type SwiftFetchStreamEvent = 'response' | 'data' | 'end'

// eslint-disable-next-line global-require
const SwiftFetch = require('../build/SwiftFetch.node') as {
  request(url: string, options?: SwiftFetchRequestOptions): Promise<FetchResponse<Buffer>>
  requestStream(url: string, options: SwiftFetchRequestOptions, callback: (event: SwiftFetchStreamEvent, data: Buffer | FetchResponse<null>) => void): Readable
}

const fetchOptionsToSwiftFetchOptions = (url: string, options?: FetchOptions): [string, SwiftFetchRequestOptions] => {
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

  return [urlString, swiftOptions]
}

export async function fetch(url: string, options?: FetchOptions): Promise<FetchResponse<Buffer>> {
  const [urlString, swiftOptions] = fetchOptionsToSwiftFetchOptions(url, options)

  const response = await SwiftFetch.request(urlString, swiftOptions)

  if (Array.isArray(response.headers['set-cookie'])) {
    for (const cookie of response.headers['set-cookie']) {
      await options?.cookieJar?.setCookie(cookie, urlString)
    }
  } else if (response.headers['set-cookie']) {
    await options?.cookieJar?.setCookie(response.headers['set-cookie'], urlString)
  }

  return response
}

export function fetchStream(url: string, options?: FetchOptions): Readable {
  const [urlString, swiftOptions] = fetchOptionsToSwiftFetchOptions(url, options)

  const readableStream = new Readable({
    read() {},
  })

  SwiftFetch.requestStream(urlString, swiftOptions, (event: SwiftFetchStreamEvent, data: Buffer | FetchResponse<null>) => {
    switch (event) {
      case 'response':
        readableStream.emit('response', data as FetchResponse<null>)
        break
      case 'data':
        readableStream.push(data)
        break
      case 'end':
        readableStream.push(null)
        break
      default:
        break
    }
  })
  return readableStream
}

class Client {
  async requestAsString(url: string, options?: FetchOptions): Promise<FetchResponse<string>> {
    const request = await fetch(url, options)
    const stringifiedBody = request.body?.toString('utf-8')

    return {
      ...request,
      body: stringifiedBody,
    }
  }

  async requestAsBuffer(url: string, options?: FetchOptions): Promise<FetchResponse<Buffer>> {
    return fetch(url, options)
  }
}

export const createHttpClient = () => new Client()
