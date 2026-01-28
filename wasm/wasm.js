// Don't leak memory, please!

const source = await fetch('wasm.wasm')

const module = await WebAssembly.instantiateStreaming(source)

const w = window

w.module = module

w.fns = w.module.instance.exports

const encoder = new TextEncoder

const encoded = encoder.encode("Hello")

w.encoded = encoded

w.mem = fns.allocate(encoded.length)

w.view = new DataView(fns.memory.buffer, w.mem, encoded.length)

w.to = (string) => {
  const utf8 = (new TextEncoder).encode(string)
  const sliceAddress = fns.allocate(utf8.length)
  const address = fns.address(sliceAddress)
  const array = new Uint8Array(fns.memory.buffer)
  for (const i of range(utf8.length)) {
    array[address + i] = utf8[i]
  }
  return sliceAddress
}

w.from = (sliceAddress) => {
  const length = fns.length(sliceAddress)
  if (length === 0) return ''
  const address = fns.address(sliceAddress)
  const decoder = new TextDecoder("utf8", { fatal: true })
  const bytes = new DataView(fns.memory.buffer, address, length)
  const utf8 = decoder.decode(bytes)
  return utf8
}

evaluate.addEventListener("click", () => {
  const input_string = w.to(input.value)
  fns.free()
  const output_string = fns.transform(w.to(input.value))
  output.value = w.from(output_string)
})

function *range(n) { for (let i = 0; i < n; i++) yield i }

