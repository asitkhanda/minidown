# Code

Inline `const x = 1` code gets a chip. Fenced blocks get highlighting per language.

## JavaScript

```js
// Fibonacci, the boring way
function fib(n) {
  return n < 2 ? n : fib(n - 1) + fib(n - 2);
}
console.log(`fib(10) = ${fib(10)}`);
```

## TypeScript

```ts
interface Note {
  title: string;
  words: number;
  draft?: boolean;
}
const note: Note = { title: "minidown", words: 42 };
```

## Python (via extension alias `py`)

```py
def greet(name: str) -> str:
    """Docstrings count as strings."""
    return f"Hello, {name}"  # and this is a comment
```

## Rust (via `rs`)

```rs
fn main() {
    let numbers: Vec<u32> = (1..=5).collect();
    println!("{:?}", numbers);
}
```

## CSS

```css
.editor {
  max-width: 42rem;
  line-height: 1.75; /* generous */
}
```

## JSON

```json
{ "name": "minidown", "version": "0.1.0", "open": true }
```

## No language

```
Plain fences still get the block styling,
just no token colors.
```
