import { Readable } from 'stream'
import FormData from 'form-data'
import type { CookieJar } from 'tough-cookie'

interface SwiftFetchRequestOptions {
  method?: 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE'
  headers?: Record<string, string>
  body?: Buffer

  timeout?: number
  redirect?: 'follow' | 'manual'
  follow?: number
  verifyCertificate?: boolean
}

type SwiftFetchStreamEvent = 'response' | 'data' | 'end' | 'error'

interface SwiftFetchClient {
  new(): SwiftFetchClient
  request(url: string, options?: SwiftFetchRequestOptions): Promise<FetchResponse<Buffer>>
  requestStream(url: string, options: SwiftFetchRequestOptions, callback: (event: SwiftFetchStreamEvent, data: Buffer | FetchResponse<null>) => void): Promise<void>
}

// eslint-disable-next-line global-require
const SwiftFetch = require('../build/SwiftFetch.node') as SwiftFetchClient

export interface FetchOptions {
  method?: 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE'
  headers?: Record<string, string>
  searchParams?: Record<string, number | string>
  form?: Record<string, number | string>
  body?: string | Buffer | FormData
  cookieJar?: CookieJar

  timeout?: number
  redirect?: 'follow' | 'manual'
  follow?: number
  verifyCertificate?: boolean
}

interface FetchResponse<T> {
  status: number
  headers: Record<string, string | string[]>
  body?: T
}

export const swiftFetchClient = new SwiftFetch()

const fetchOptionsToSwiftFetchOptions = (url: string, options?: FetchOptions): [string, SwiftFetchRequestOptions] => {
  let urlString = url
  const swiftOptions: SwiftFetchRequestOptions = {
    method: options?.method,
    headers: options?.headers,
    timeout: options?.timeout,
    redirect: options?.redirect,
    follow: options?.follow,
    verifyCertificate: options?.verifyCertificate,
  }

  if (options?.cookieJar) {
    swiftOptions.headers = {
      ...swiftOptions.headers,
      Cookie: options.cookieJar.getCookieStringSync(url),
    }
  }

  if (options?.form) {
    const formData = new FormData()

    for (const [key, value] of Object.entries(options.form)) {
      formData.append(key, value)
    }

    swiftOptions.headers = formData.getHeaders(swiftOptions.headers)
    swiftOptions.body = formData.getBuffer()
  } else if (options?.body?.constructor.name === 'FormData') {
    swiftOptions.headers = (options.body as FormData).getHeaders(swiftOptions.headers)
    swiftOptions.body = (options.body as FormData).getBuffer()
  } else if (typeof options?.body === 'string' || options?.body instanceof String) {
    swiftOptions.body = Buffer.from(options.body)
  } else if (Buffer.isBuffer(options?.body)) {
    swiftOptions.body = options?.body
  } else if (options?.body) {
    throw new Error('Invalid body type')
  }

  if (options?.searchParams) {
    const searchParams = new URLSearchParams(options.searchParams as Record<string, string>)
    urlString += `?${searchParams.toString()}`
  }

  return [urlString, swiftOptions]
}

export async function fetch(url: string, options?: FetchOptions): Promise<FetchResponse<Buffer>> {
  const [urlString, swiftOptions] = fetchOptionsToSwiftFetchOptions(url, options)

  const response = await swiftFetchClient.request(urlString, swiftOptions)

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
