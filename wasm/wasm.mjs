const source = fs.readFileSync('wasm.wasm')
const typedArray = new Uint8Array(source)

const module = await WebAssembly.instantiate(typedArray, {
  env: {
    print: (x) => console.log(`Result: ${x}`)
  }
})

module.instance.exports.add(1, 2)
