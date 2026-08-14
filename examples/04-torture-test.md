# Torture Test

Deliberately awkward markdown. Notes in *(italics)* say what should happen.

## Escapes and near-misses

\*Not italic\* — escaped asterisks stay literal.
A lone * asterisk and 2 * 3 = 6 don't become emphasis.
**Unclosed bold stays raw because it never closes.
snake_case_words don't italicize mid-word.

## Nesting

**Bold with *italic inside* it** and *italic with **bold inside** it*.
`code with **no bold** inside` *(emphasis must not render inside code)*.
> A quote with **bold**, `code`, and a [link](https://example.com) inside.

## Lists that push their luck

- A bullet with **bold** and `code`
  1. Ordered inside unordered
  2. Still numbered
     - [ ] A task nested two levels deep
- > A blockquote inside a bullet

## Setext headings

Heading One
===========

Heading Two
-----------

*(The underline is the syntax — it hides when you leave the line.)*

## Code fence containing backticks

````md
A fence made of four backticks can contain ```three``` safely.
````

## Table with formatting in cells

| Style | Sample |
| --- | --- |
| bold | **not rendered in the grid yet** |
| code | `also raw in cells` |

*(Known limitation: cell contents render plain for now.)*

## Extended syntax edge cases

Footnote reference[^1] renders superscript; the definition below stays readable.

[^1]: A footnote definition line.

Math like $e^{i\pi} + 1 = 0$ renders inline, but $5 and $10 stay dollars,
and an unclosed $ dangling alone stays literal.

## Unicode

Emoji 🎉, accents (café, naïve), CJK (日本語テスト), RTL (مرحبا), and a really long word: pneumonoultramicroscopicsilicovolcanoconiosis.
