import { requestAsString } from '../dist'

test('Fetch JSON document', async () => {
  const response = await requestAsString('https://httpbin.org/json')

  expect(response.statusCode).toBe(200)
  expect(response.body).toBeDefined()
  expect(JSON.parse(response.body)).toBeDefined()
})
