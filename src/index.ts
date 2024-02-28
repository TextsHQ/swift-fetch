import { Readable } from 'stream'
import FormData from 'form-data'
import type { FetchOptions, FetchResponse } from '@textshq/platform-sdk'
import { mapBodyToBuffer } from './utils'

interface SwiftFetchRequestOptions {
  method?: FetchOptions['method']
  headers?: Record<string, string>
  body?: Buffer

  followRedirect?: boolean
  skipCertificateVerification?: boolean
  pinnedCertificates?: Buffer[]
}

interface SwiftFetchResponse<T> extends FetchResponse<T> {
  newCookies?: Record<string, string[]>
}

type SwiftFetchStreamEvent = 'response' | 'data' | 'end' | 'error'

interface ISwiftFetchClient {
  new(): ISwiftFetchClient
  request(url: string, options?: SwiftFetchRequestOptions): Promise<SwiftFetchResponse<Buffer>>
  requestStream(url: string, options: SwiftFetchRequestOptions, callback: (event: SwiftFetchStreamEvent, data: Buffer | SwiftFetchResponse<null>) => void): Promise<void>
}

// eslint-disable-next-line global-require
const SwiftFetchNative = require('../build/Release/SwiftFetch.node') as ISwiftFetchClient

const client = new SwiftFetchNative()

async function fetchOptionsToSwiftFetchOptions(url: string, options?: FetchOptions): Promise<[string, SwiftFetchRequestOptions]> {
  let urlString = url
  const swiftOptions: SwiftFetchRequestOptions = {
    method: options?.method,
    headers: options?.headers,
    followRedirect: options?.followRedirect,
    skipCertificateVerification: process.env.NODE_TLS_REJECT_UNAUTHORIZED === '0',
    pinnedCertificates: options?.pinnedCertificates,
  }

  if (options?.cookieJar) {
    swiftOptions.headers = {
      ...swiftOptions.headers,
      Cookie: options.cookieJar.getCookieStringSync(url),
    }
  }

  if (options?.body) {
    swiftOptions.body = await mapBodyToBuffer(options.body)
    if (options?.body.constructor.name === 'FormData') {
      swiftOptions.headers = (options.body as FormData).getHeaders(swiftOptions.headers)
    }
  } else if (options?.form) {
    for (const [key, val] of Object.entries(options.form)) {
      if (val == null || val === undefined) delete options.form[key]
      const body = new URLSearchParams(options.form as Record<string, string>)
      if (swiftOptions.headers) {
        swiftOptions.headers['content-type'] = 'application/x-www-form-urlencoded'
      } else {
        swiftOptions.headers = {
          'content-type': 'application/x-www-form-urlencoded',
        }
      }
      swiftOptions.body = Buffer.from(body.toString())
    }
  }

  if (options?.searchParams) {
    const searchParams = new URLSearchParams(options.searchParams as Record<string, string>)
    urlString += `?${searchParams.toString()}`
  }

  return [urlString, swiftOptions]
}

async function internalFetch(swiftFetchClient: ISwiftFetchClient, url: string, options?: FetchOptions): Promise<FetchResponse<Buffer>> {
  const [urlString, swiftOptions] = await fetchOptionsToSwiftFetchOptions(url, options)
  const response = await swiftFetchClient.request(urlString, swiftOptions)

  if (options?.cookieJar) {
    if (response.newCookies) {
      for (const [cookieUrl, cookies] of Object.entries(response.newCookies)) {
        for (const cookie of cookies) {
          await options?.cookieJar?.setCookie(cookie, cookieUrl, { ignoreError: true })
        }
      }
    }

    if (response.headers['set-cookie']) {
      for (const cookie of response.headers['set-cookie']) {
        await options?.cookieJar?.setCookie(cookie, urlString, { ignoreError: true })
      }
    }
  }

  return response
}

export async function fetch(url: string, options?: FetchOptions): Promise<FetchResponse<Buffer>> {
  return internalFetch(client, url, options)
}

export async function fetchStream(url: string, options?: FetchOptions): Promise<Readable> {
  const [urlString, swiftOptions] = await fetchOptionsToSwiftFetchOptions(url, options)

  const readableStream = new Readable({
    read() {},
  })

  client.requestStream(urlString, swiftOptions, (event: SwiftFetchStreamEvent, data: Buffer | FetchResponse<null>) => {
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
      case 'error':
        readableStream.emit('error', data)
        break
      default:
        break
    }
  })
  return readableStream
}

export class SwiftFetchClient {
  private client = new SwiftFetchNative()

  async requestAsString(url: string, options?: FetchOptions): Promise<FetchResponse<string>> {
    const response = await this.requestAsBuffer(url, options)
    return {
      ...response,
      body: response.body?.toString('utf8'),
    }
  }

  async requestAsBuffer(url: string, options?: FetchOptions): Promise<FetchResponse<Buffer>> {
    return internalFetch(this.client, url, options)
  }
}
