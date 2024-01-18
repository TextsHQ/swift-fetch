import { Readable } from 'stream'
import FormData from 'form-data'
import type { FetchOptions, FetchResponse } from '@textshq/platform-sdk'
import { mapBodyToBuffer } from './utils'

interface SwiftFetchRequestOptions {
  method?: FetchOptions['method']
  headers?: Record<string, string>
  body?: Buffer

  timeout?: number
  followRedirect?: boolean
  verifyCertificate?: boolean
}

type SwiftFetchStreamEvent = 'response' | 'data' | 'end' | 'error'

interface SwiftFetchClient {
  new(): SwiftFetchClient
  request(url: string, options?: SwiftFetchRequestOptions): Promise<FetchResponse<Buffer>>
  requestStream(url: string, options: SwiftFetchRequestOptions, callback: (event: SwiftFetchStreamEvent, data: Buffer | FetchResponse<null>) => void): Promise<void>
}

// eslint-disable-next-line global-require
const SwiftFetch = require('../build/Release/SwiftFetch.node') as SwiftFetchClient

const swiftFetchClient = new SwiftFetch()

async function fetchOptionsToSwiftFetchOptions(url: string, options?: FetchOptions): Promise<[string, SwiftFetchRequestOptions]> {
  let urlString = url
  const swiftOptions: SwiftFetchRequestOptions = {
    method: options?.method,
    headers: options?.headers,
    timeout: options?.timeout,
    followRedirect: options?.followRedirect,
    verifyCertificate: options?.verifyCertificate,
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

export async function fetch(url: string, options?: FetchOptions): Promise<FetchResponse<Buffer>> {
  const [urlString, swiftOptions] = await fetchOptionsToSwiftFetchOptions(url, options)

  const response = await swiftFetchClient.request(urlString, swiftOptions)

  if (response.headers['set-cookie']) {
    for (const cookie of response.headers['set-cookie']) {
      await options?.cookieJar?.setCookie(cookie, urlString, { ignoreError: true })
    }
  }

  return response
}

export async function fetchStream(url: string, options?: FetchOptions): Promise<Readable> {
  const [urlString, swiftOptions] = await fetchOptionsToSwiftFetchOptions(url, options)

  const readableStream = new Readable({
    read() {},
  })

  swiftFetchClient.requestStream(urlString, swiftOptions, (event: SwiftFetchStreamEvent, data: Buffer | FetchResponse<null>) => {
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
