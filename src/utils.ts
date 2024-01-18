import type { FetchOptions } from '@textshq/platform-sdk'
import type FormData from 'form-data'
import { Readable } from 'stream'

export const isReadableStream = (stream: any): stream is Readable =>
  typeof stream._read === 'function' && stream.readable !== false

export const isString = (value: any): value is string => typeof value === 'string'

export async function readableStreamToBuffer(stream: Readable): Promise<Buffer> {
  const buffers: Buffer[] = []
  for await (const chunk of stream) {
    buffers.push(chunk)
  }
  return Buffer.concat(buffers)
}

export async function mapBodyToBuffer(body: FetchOptions['body']) {
  if (!body) return
  if (Buffer.isBuffer(body)) return body
  if (typeof body === 'string' || body instanceof String) return Buffer.from(body)
  if (body.constructor.name === 'FormData') return (body as FormData).getBuffer()
  if (body instanceof Readable) return readableStreamToBuffer(body)
}
