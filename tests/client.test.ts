import crypto from 'crypto'
import FormData from 'form-data'
import { CookieJar } from 'tough-cookie'
import type { Readable } from 'stream'
import type { FetchOptions, FetchResponse } from '@textshq/platform-sdk'

import { fetch, fetchStream } from '../src'

const baseUrl = 'https://httpbin.1conan.com'

test.concurrent('Fetch JSON document', async () => {
  const response = await fetch(`${baseUrl}/json`)

  expect(response.statusCode).toBe(200)
  expect(response.body).toBeDefined()
  expect(JSON.parse(response.body!.toString())).toBeDefined()
})

describe('Compressions', () => {
  test.concurrent('GZip', async () => {
    const response = await fetch(`${baseUrl}/gzip`)

    expect(response.statusCode).toBe(200)
    expect(response.body).toBeDefined()
    expect(response.body!.toString().startsWith('{')).toBe(true)
  })

  // TODO: add brotli support to swift-nio-extras
  // test.concurrent('Brotli', async () => {
  //   const response = await fetch(`${baseUrl}/brotli`)

  //   expect(response.statusCode).toBe(200)
  //   expect(response.body).toBeDefined()
  //   expect(response.body!.toString().startsWith('{')).toBe(true)
  // })
})

describe('Request methods', () => {
  const methods: FetchOptions['method'][] = ['GET', 'POST', 'PATCH', 'PUT', 'DELETE']

  for (const method of methods) {
    // eslint-disable-next-line @typescript-eslint/no-loop-func
    test.concurrent(method as string, async () => {
      const response = await fetch(`${baseUrl}/${method!.toLowerCase()}`, {
        method,
      })

      expect(response.statusCode).toBe(200)
    })
  }
})

test.concurrent('Request headers', async () => {
  const response = await fetch(`${baseUrl}/headers`, {
    headers: {
      foo: 'bar',
      lemon: 'strawberry',
    },
  })

  expect(response.statusCode).toBe(200)

  expect(response.body).toBeDefined()

  const body = JSON.parse(response.body!.toString())

  expect(body.headers.Foo).toBe('bar')
  expect(body.headers.Lemon).toBe('strawberry')
})

test.concurrent('Response headers', async () => {
  const response = await fetch(`${baseUrl}/response-headers?foo=bar&foo=test&bar=foo`)

  expect(response.statusCode).toBe(200)
  expect(response.headers.bar).toBe('foo')
})

test.concurrent('Request form', async () => {
  const response = await fetch(`${baseUrl}/post`, {
    method: 'POST',
    form: {
      foo: 'bar',
      test: 2,
    },
  })

  expect(response.statusCode).toBe(200)
  expect(response.body).toBeDefined()

  const body = JSON.parse(response.body!.toString())

  expect(body.form.foo).toBe('bar')
})

test.concurrent('Request cookie handling', async () => {
  const jar = new CookieJar()

  const response = await fetch(`${baseUrl}/cookies/set`, {
    cookieJar: jar,
    searchParams: {
      foo: 'bar',
      lemon: 'juice',
      strawberry: 'blueberry',
    },
    followRedirect: false,
  })

  expect(response.statusCode).toBe(302)
  expect(response.headers['set-cookie']).toHaveLength(3)

  const cookieStr = jar.getCookieStringSync(`${baseUrl}`)

  expect(cookieStr).toHaveLength(42)
})

test.concurrent('Request cookie handling (followRedirect)', async () => {
  const jar = new CookieJar()

  const response = await fetch(`${baseUrl}/cookies/set`, {
    cookieJar: jar,
    searchParams: {
      foo: 'bar',
      lemon: 'juice',
      strawberry: 'blueberry',
    },
  })

  expect(response.statusCode).toBe(200)

  const cookieStr = jar.getCookieStringSync(`${baseUrl}`)

  expect(cookieStr).toHaveLength(42)
})

test.concurrent('Request multi-part', async () => {
  const response = await fetch(`${baseUrl}/image/webp`)

  expect(response.statusCode).toBe(200)
  expect(response.body?.constructor.name).toBe('Buffer')
  expect(response.body!.length).toBeGreaterThan(10000)

  const form = new FormData()

  form.append('foo', 'bar')
  form.append('blizzy', response.body)

  const response_2 = await fetch(`${baseUrl}/anything`, {
    method: 'POST',
    body: form,
  })

  expect(response_2.body).toBeDefined()
  expect(response_2.body!.length).toBeGreaterThan(10000)
})

test.concurrent('Response binary data', async () => {
  const response = await fetch(`${baseUrl}/image/webp`)

  expect(response.statusCode).toBe(200)
  expect(response.body?.constructor.name).toBe('Buffer')
  expect(response.body?.length).toBeGreaterThan(10000)
})

describe('Image Streaming', () => {
  const imagesWithHashes = [
    ['webp', '567cfaf94ebaf279cea4eb0bc05c4655021fb4ee004aca52c096709d3ba87a63'],
    ['jpeg', 'c028d7aa15e851b0eefb31638a1856498a237faf1829050832d3b9b19f9ab75f'],
    ['png', '541a1ef5373be3dc49fc542fd9a65177b664aec01c8d8608f99e6ec95577d8c1'],
  ]

  const streamToBuffer = (stream: Readable) => new Promise<[FetchResponse<null>, Buffer]>((resolve, reject) => {
    const chunks: Buffer[] = []
    let response: FetchResponse<null>

    stream.on('response', (res: FetchResponse<null>) => {
      response = res
    })

    stream.on('data', (chunk: Buffer) => {
      chunks.push(chunk)
    })

    stream.on('end', () => {
      resolve([response, Buffer.concat(chunks)])
    })

    stream.on('error', (err: Error) => {
      reject(err)
    })
  })

  for (const [imageType, hash] of imagesWithHashes) {
    // eslint-disable-next-line @typescript-eslint/no-loop-func
    test.concurrent(imageType, async () => {
      const stream = await fetchStream(`${baseUrl}/image/${imageType}`)

      const [response, buffer] = await streamToBuffer(stream)

      const bufferHash = crypto.createHash('sha256').update(buffer).digest('hex')

      expect(bufferHash).toBe(hash)
      expect(response.statusCode).toBe(200)
    })
  }
})

describe('SSL Tests', () => {
  test('Pinned Certificate', async () => {
    const certificate = `
    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
    9qfgAJizyy3kqM4lOwBH
    `

    const response = await fetch('https://chat.signal.org', {
      pinnedCertificates: [Buffer.from(certificate.replace(/\n/g, '').trim(), 'base64')],
    })
    expect(response.statusCode).toBe(404)
  })
})
