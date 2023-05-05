import FormData from 'form-data'
import { CookieJar } from 'tough-cookie'
import { fetch, FetchOptions } from '../src'

const baseUrl = 'https://httpbin.org'

test('Fetch JSON document', async () => {
  const response = await fetch(`${baseUrl}/json`)

  expect(response.status).toBe(200)
  expect(response.body).toBeDefined()
  expect(JSON.parse(response.body!.toString())).toBeDefined()
})

describe('Compressions', () => {
  test('GZip', async () => {
    const response = await fetch(`${baseUrl}/gzip`)

    expect(response.status).toBe(200)
    expect(response.body).toBeDefined()
    expect(response.body!.toString().startsWith('{')).toBe(true)
  })

  // TODO: add brotli support to swift-nio-extras
  // test('Brotli', async () => {
  //   const response = await fetch(`${baseUrl}/brotli`)

  //   expect(response.status).toBe(200)
  //   expect(response.body).toBeDefined()
  //   expect(response.body!.toString().startsWith('{')).toBe(true)
  // })
})

describe('Request methods', () => {
  const methods: FetchOptions['method'][] = ['GET', 'POST', 'PATCH', 'PUT', 'DELETE']

  for (const method of methods) {
    // eslint-disable-next-line @typescript-eslint/no-loop-func
    test(method as string, async () => {
      const response = await fetch(`${baseUrl}/${method!.toLowerCase()}`, {
        method,
      })

      expect(response.status).toBe(200)
    })
  }
})

test('Request headers', async () => {
  const response = await fetch(`${baseUrl}/headers`, {
    headers: {
      foo: 'bar',
      lemon: 'strawberry',
    },
  })

  expect(response.status).toBe(200)

  expect(response.body).toBeDefined()

  const body = JSON.parse(response.body!.toString())

  expect(body.headers.Foo).toBe('bar')
  expect(body.headers.Lemon).toBe('strawberry')
})

test('Response headers', async () => {
  const response = await fetch(`${baseUrl}/response-headers?foo=bar&foo=test&bar=foo`)

  expect(response.status).toBe(200)
  expect(response.headers.bar).toBe('foo')
})

test('Request form', async () => {
  const response = await fetch(`${baseUrl}/post`, {
    method: 'POST',
    form: {
      foo: 'bar',
      test: 2,
    },
  })

  expect(response.status).toBe(200)
  expect(response.body).toBeDefined()

  const body = JSON.parse(response.body!.toString())

  expect(body.form.foo).toBe('bar')
})

test('Request cookie handling', async () => {
  const jar = new CookieJar()

  const response = await fetch(`${baseUrl}/cookies/set`, {
    cookieJar: jar,
    searchParams: {
      foo: 'bar',
      lemon: 'juice',
      strawberry: 'blueberry',
    },
  })

  expect(response.status).toBe(302)
  expect(response.headers['set-cookie']).toHaveLength(3)

  const cookieStr = jar.getCookieStringSync(`${baseUrl}`)

  expect(cookieStr).toHaveLength(42)
}, 60000)

test('Request multi-part', async () => {
  const response = await fetch(`${baseUrl}/image/webp`)

  expect(response.status).toBe(200)
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
}, 40000)

test('Response binary data', async () => {
  const response = await fetch(`${baseUrl}/image/webp`)

  expect(response.status).toBe(200)
  expect(response.body?.constructor.name).toBe('Buffer')
  expect(response.body?.length).toBeGreaterThan(10000)
}, 20000)
