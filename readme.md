# soml-applescript

> Read and write [SOML](https://soml.sh), a config format for humans, in AppleScript

> [!NOTE]
> The format is a draft.

## Highlights

- Strict: enforces every rule of the specification, with the same error positions and messages as the JavaScript reference implementation
- Exact: every int64, date, instant, and duration survives, `3` and `3.0` stay different, and keys keep their exact spelling
- Native: an object is a record, so a value is `|port| of |server| of config`
- Canonical: `encodeCanonical()` gives equal text for equal values, and `encode()` keeps the order of a record's labels
- Safe: invalid UTF-8 is an error, deep input cannot overflow the stack, and the caller's text item delimiters are kept
- A script library with terminology, for AppleScript 2.8 on macOS 12 or later

## Install

[Download SOML.scptd.zip](https://github.com/soml-lang/soml-applescript/releases/latest/download/SOML.scptd.zip), unzip it, and move `SOML.scptd` to `~/Library/Script Libraries`.

Or build it from source:

```sh
git clone https://github.com/soml-lang/soml-applescript
cd soml-applescript
make install
```

This compiles the library to `~/Library/Script Libraries/SOML.scptd`. A failed install keeps the previous version, and a replaced version goes to the Trash. The `make` commands require the Xcode Command Line Tools and macOS 15 or later, for the `trash` command.

## Usage

```
# config.soml
name: 'api-gateway'
replicas: 3
timeout: 1m30s
launch-date: 2027-09-19
server: {
	host: 'localhost'
	port: 8080
}
servers: [
	{host: 'a.internal'}
	{host: 'b.internal'}
]
deps: {'socket.io': '^4'}
```

```applescript
use AppleScript version "2.8"
use scripting additions
use soml : script "SOML"

set config to soml's decodeFile("/path/to/config.soml")

|name| of config
--=> "api-gateway"

|port| of |server| of config
--=> 8080

|host| of item 2 of |servers| of config
--=> "b.internal"

|socket.io| of |deps| of config
--=> "^4"

soml's toSeconds(|timeout| of config)
--=> 90.0
```

> [!TIP]
> Always write keys in bars, as in `|port| of |server| of config`. Without bars, a key that is also an AppleScript or scripting addition term, such as `name`, `id`, `host`, `port`, or `timeout`, means something else.

To write:

```applescript
soml's encode({|name|:"api-gateway", replicas:3, ratio:0.5, tags:{"edge", "public"}})
```

```
name: 'api-gateway'
replicas: 3
ratio: 0.5
tags: [
	'edge'
	'public'
]
```

## Types

| SOML | AppleScript |
|---|---|
| object | record, with the keys as labels, in document order |
| array | list |
| string | text |
| int | integer, from -536870912 to 536870911, and otherwise `{class:SOML int, value:"9007199254740993"}` |
| float | real, including infinity and -infinity |
| bool | boolean |
| null | `missing value` |
| date | `{class:SOML date, value:"2027-09-19"}`, without time or timezone |
| instant | `{class:SOML instant, value:"2026-09-19T12:00:00Z"}`, in UTC |
| duration | `{class:SOML duration, value:"1h30m"}` |

`SOML int`, `SOML date`, `SOML instant`, `SOML duration`, and `SOML object` are classes in the library's terminology, so `class of value is SOML instant` works in a script with `use soml : script "SOML"`. The `value` of each is its canonical SOML spelling. A `SOML date` is a calendar day in years 0001–9999, not an AppleScript `date`, which is an instant. Quoted dates stay strings.

An object that a record cannot hold is `{class:SOML object, entries:{{key, value}, …}}`, which `entries()` reads like a record. That is:

- an empty object, because AppleScript has no empty record (`{}` is a list),
- an object with two keys that differ only in ASCII letter case, such as `a` and `A`, because AppleScript ignores case in labels,
- an object with a key that AppleScript would spell differently. AppleScript keeps the first spelling of a label it sees for the life of the process, so after a record with the label `URL`, a new label `url` becomes `URL`. So whether an object is a record can depend on what the process read before,
- every object of a document with a label that AppleScript cannot expose, such as some long labels,
- every object of a document with more than 4,000 distinct keys, or read when AppleScript has no room for new labels (see Limitations),
- every object of a document with a string or key that starts with U+FEFF or U+FFFE, because the Apple event that gives a record its labels changes these characters.

An integer that AppleScript arithmetic makes above 1073741823 or below -1073741824 is a real, as in `1000 * 1000 * 1000`, so it is written as a float, `1000000000.0`. Use `{class:SOML int, value:"1000000000"}` for an int of any size.

`encode()` and `encodeCanonical()` also take:

- an AppleScript `date`, as an instant (in local time, with whole seconds),
- `null`, as null,
- a record label that is a keyword, such as `name` or `button returned`, as the key it spells,
- the tagged values in any spelling that SOML accepts, as in `{class:SOML int, value:"0xFF"}` and `{class:SOML instant, value:"2026-09-19T14:00:00+02:00"}`.

## API

Handlers resolve loop and item references passed as their argument. To store a loop variable in a list or record, use `contents of loopVariable`.

### decode(text)

Read a document from text. Returns a record, a list, or a `SOML object`.

### decodeFile(file)

Read a document from a file, given as a POSIX path, a file, or an alias, as UTF-8. Invalid UTF-8 is an error at its position, where `read … as «class utf8»` accepts it.

### encode(value)

Write a record, a list, or a `SOML object` as a document, keeping the order of record labels. The text ends with a line feed.

### encodeCanonical(value)

Write a value in [canonical form](https://github.com/soml-lang/soml/blob/main/spec.md#canonical-form): one exact text for each value, with object keys sorted, for hashing and comparing.

### entries(record)

The keys and values of a record or a `SOML object`, in order: `{{key, value}, …}`. Use it to read an object whose keys are not known in advance, as AppleScript cannot list the labels of a record.

```applescript
repeat with theEntry in soml's entries(|deps| of config)
	set {theName, theVersion} to theEntry
end repeat
```

### fromEntries(list)

A record with the given keys and values: `{{key, value}, …}`. Gives a `SOML object` where a record cannot hold or expose the keys exactly, as described under Types.

Opaque values may use the `SOML object` form so their original values are preserved.

```applescript
soml's fromEntries({{"socket.io", "^4"}, {"react", "^19"}})
--=> {|socket.io|:"^4", react:"^19"}
```

### toNumber(value)

An int as an AppleScript number: an integer as it is, and a `SOML int` as a real up to 2^53. A larger `SOML int` is an error.

### toDate(value)

A `SOML instant` as an AppleScript date, in local time. A fraction of a second is dropped.

### toSeconds(value)

A `SOML duration` as a number of seconds, a real. It is exact up to about 104 days, and rounded beyond that.

### Errors

| Number | Error |
|---|---|
| 1 | The document is not valid. The message ends with the position, as in `… at line 2, column 11`, and `from` is `{reason:…, \|line\|:2, \|column\|:11}`. Lines and columns start at 1, and columns count Unicode scalar values. |
| 2 | The value cannot be written or converted, such as a script object, a text with a carriage return or a lone surrogate, NaN, a duplicate key, a `SOML int` too large for an exact number, or a malformed tagged value. The message names the value or its path, as in `servers[0].ratio`. |
| -1703 | A handler got an argument of the wrong type, or a tagged value whose text is not valid. |
| -43 | `decodeFile()` could not read the file. |
| -2707 | AppleScript has no room for new record labels (see Limitations). |

```applescript
try
	soml's decode("name: api-gateway")
on error message number errorNumber from details
	message
	--=> "Unexpected “api-gateway”. A string value must be quoted, as in 'api-gateway' at line 1, column 7"
	|line| of details
	--=> 1
end try
```

## Recipes

### Change a value and write the file

```applescript
set config to soml's decodeFile("/path/to/config.soml")
set |port| of |server| of config to 9090
set encodedConfig to soml's encode(config)

set theFile to open for access (POSIX file "/path/to/config.soml") with write permission
try
	set eof theFile to 0
	write encodedConfig to theFile as «class utf8»
	close access theFile
on error message number errorNumber
	close access theFile
	error message number errorNumber
end try
```

This keeps the order of the keys, but not comments or layout.

### Hash a config

Comments, key order, and spelling do not change the canonical form:

```applescript
do shell script "printf %s " & quoted form of soml's encodeCanonical(config) & " | shasum -a 256"
```

## Limitations

- **No formatter or editor.** Comments and layout are not kept.
- **Speed.** AppleScript is slow, so a few-kilobyte config takes about 16 ms to read, and 733 KB takes about 3 seconds. See the benchmark.
- **Floats.** JavaScriptCore converts floats, because AppleScript's own conversions round and use the locale (`0,5` in some regions). `-0.0` reads as `0.0`, as the specification says.
- **AppleScript dates.** An AppleScript date is in local time with whole seconds, so `toDate()` drops a fraction of a second. In the hour that repeats when daylight saving time ends, the system picks one of the two instants.
- **Record labels.** A process holds about 8,000 distinct record labels, counting those of every loaded script. When the table is full, AppleScript fails with error -2707, “Internal table overflow”, also in AppleScriptObjC calls. The library does not add labels for documents and `fromEntries()` lists with more than 4,000 keys, but many smaller documents with different keys, or a script that makes many records, can still fill the table. It then stays full for the life of the process, so later documents give `SOML object`s.
- **Surrogates.** `encode()` rejects a lone surrogate in a string, but can miss one at the end of a text, because AppleScript reports the codes of such a text inconsistently.

## Benchmark

```sh
make bench
make bench FIXTURE=service SAMPLES=5
```

Median time per document for the [shared benchmark fixtures](https://github.com/soml-lang/soml/tree/main/benchmark) and the same data as JSON, on an Apple M4 Pro with macOS 27.0. `service` is a 3 KB config, `platform` a 35 KB config with many comments, and `earthquakes` a 733 KB GeoJSON feed. The times are rough. Lower is better.

| | SOML for AppleScript | NSJSONSerialization |
|---|--:|--:|
| Read `service` | 16 ms | 247 µs |
| Read `platform` | 110 ms | 1.5 ms |
| Read `earthquakes` | 2.9 s | 54 ms |
| Write `service` | 14 ms | 265 µs |
| Write `platform` | 112 ms | 1.7 ms |
| Write `earthquakes` | 7.9 s | 60 ms |

`NSJSONSerialization` is native code with a much smaller grammar, so it is the ceiling, not a competitor. Its times include making AppleScript records and lists. AppleScript has no TOML library in common use.

`FIXTURE` is `service`, `platform`, `earthquakes`, or `all` (the default). `SAMPLES` sets the sample count (default: 21 for `service`, 11 for `platform`, and 5 for `earthquakes`).

## Development

```sh
make test
# Or:
npm test
```

Requires Node.js 26 or later, with no npm dependencies. Runs the [conformance suite](test/conformance) with Node.js and the API tests in AppleScript. Set `SHOW_REASONS=1` to print the error messages that differ from the reference. Use `make test NODE=/path/to/node` to select a Node.js executable.

To update [`test/conformance`](test/conformance), check out [`soml`](https://github.com/soml-lang/soml) next to this repository and run `../soml/sync-conformance.sh test/conformance`. To update the benchmark fixtures, run `rsync --archive --delete ../soml/benchmark/ bench/fixtures/`.

The library is one file, [`source/SOML.applescript`](source/SOML.applescript), and its terminology is [`source/SOML.sdef`](source/SOML.sdef).
