#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
. "$ROOT/src/55-confluence-hooks.sh"
hash() { printf '%s' "$1" | confluence_hook_hash; }
matches() {
  actual=$(printf '%s' "$2" | confluence_hook_prose_hash) || actual=
  [ "$actual" = "$(hash "$1")" ]
}
matches 'Owner BE_Cuong; Asia/Ho_Chi_Minh' 'Owner BE\_Cuong; Asia/Ho\_Chi\_Minh'
matches 'See [BB-64](https://example.com/BB-64). Owner BE_Cuong' 'See [BB-64](https://example.com/BB-64). Owner BE\_Cuong'
matches 'Owner BE_Cuong
```http
GET /a_b
```
`a_b`' 'Owner BE\_Cuong
```http
GET /a_b
```
`a_b`'
for pair in \
  'value_a|value\_b' \
  '`a_b`|`a\_b`' \
  'https://example.com/a_b|https://example.com/a\_b' \
  'www.example.com/a_b|www.example.com/a\_b' \
  'a_b@example.com|a\_b@example.com' \
  '[a_b]|[a\_b]' \
  '$a_b$|$a\_b$' \
  '<a_b>|<a\_b>' \
  '    a_b|    a\_b' \
  '> a_b|> a\_b' \
  'a_b|a\\_b'; do
  if matches "${pair%%|*}" "${pair#*|}"; then
    printf 'FAIL: accepted changed or unsupported Markdown: %s\n' "$pair" >&2
    exit 1
  fi
done
if matches '```text
a_b
```' '```text
a\_b
```'; then exit 1; fi
if matches '`code
a_b
end`' '`code
a\_b
end`'; then exit 1; fi
if matches '[foo
bar_baz]: https://example.com

[foo bar_baz]' '[foo
bar\_baz]: https://example.com

[foo bar_baz]'; then exit 1; fi
if matches '```
````
```
a_b
```
```' '```
````
```
a\_b
```
```'; then exit 1; fi
printf '%s\n' 'PASS: conservative Confluence prose escapes'
