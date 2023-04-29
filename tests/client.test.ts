import { request } from '../dist'

test('Fetch JSON document', async () => {
  const response = await request('https://httpbin.org/json')

  expect(response.statusCode).toBe(200)
  expect(response.body).toBeDefined()
  expect(JSON.parse(response.body.toString())).toBeDefined()
})

describe('Compressions', () => {
  test('GZip', async () => {
    const response = await request('https://httpbin.org/gzip')

    expect(response.statusCode).toBe(200)
  })

  test('Brotli', async () => {
    const response = await request('https://httpbin.org/brotli')

    expect(response.statusCode).toBe(200)
  })
})

describe('Request methods', () => {
  const methods = ['GET', 'POST', 'PATCH', 'PUT', 'DELETE']

  for (const method of methods) {
    // eslint-disable-next-line @typescript-eslint/no-loop-func
    test(method, async () => {
      const response = await request(`https://httpbin.org/${method.toLowerCase()}`, {
        method,
      })

      expect(response.statusCode).toBe(200)
    })
  }
})

test('Request headers', async () => {
  const response = await request('https://httpbin.org/headers', {
    headers: {
      foo: 'bar',
      lemon: 'strawberry',
    },
  })

  expect(response.statusCode).toBe(200)

  const body = JSON.parse(response.body.toString())

  expect(body.headers.Foo).toBe('bar')
  expect(body.headers.Lemon).toBe('strawberry')
})

test('Response headers', async () => {
  const response = await request('https://httpbin.org/response-headers?foo=bar&foo=test&bar=foo')

  expect(response.statusCode).toBe(200)
  // Node.js expects either string or string[] but Swift doesn't return an array
  expect(response.headers.foo).toBe('bar, test')
  expect(response.headers.bar).toBe('foo')
})
