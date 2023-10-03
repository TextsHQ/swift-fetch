import crypto from 'crypto'
import FormData from 'form-data'
import { CookieJar } from 'tough-cookie'
import type { Readable } from 'stream'

import { fetch, FetchOptions, FetchResponse, fetchStream } from '../src'

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
      const stream = fetchStream(`${baseUrl}/image/${imageType}`)

      const [response, buffer] = await streamToBuffer(stream)

      const bufferHash = crypto.createHash('sha256').update(buffer).digest('hex')

      expect(bufferHash).toBe(hash)
      expect(response.statusCode).toBe(200)
    })
  }
})
