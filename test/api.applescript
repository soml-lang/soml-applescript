(*
Tests the handlers of the library, beyond the conformance suite.

	make api
*)

use AppleScript version "2.8"
use framework "Foundation"
use scripting additions
use soml : script "SOML"

property failures : {}
property testCount : 0

on run
	set failures to {}
	set testCount to 0
	testDecodeValues()
	testDecodeErrors()
	testTaggedValues()
	testKeyCase()
	testEncode()
	testEncodeErrors()
	testEntries()
	testConversions()
	testDecodeFile()
	testInputEdgeCases()
	testValueEdgeCases()
	testCallerState()
	-- Last, because it fills AppleScript's table of record labels for the rest of the process.
	testLabelTable()
	set summary to (testCount as text) & " tests, " & ((count failures) as text) & " failures"
	if failures is not {} then
		set previousDelimiters to AppleScript's text item delimiters
		set AppleScript's text item delimiters to linefeed
		set report to failures as text
		set AppleScript's text item delimiters to previousDelimiters
		error summary & linefeed & report
	end if
	log summary
	return summary
end run

on check(theName, actual, expected)
	set testCount to testCount + 1
	considering case, diacriticals, hyphens, punctuation and white space
		set isEqual to (actual = expected) and (class of actual = class of expected)
	end considering
	if not isEqual then
		set end of failures to theName & ": expected " & display(expected) & ", got " & display(actual)
	end if
end check

on checkError(theName, theScript, expectedNumber, expectedText)
	set testCount to testCount + 1
	try
		run theScript
		set end of failures to theName & ": expected an error"
	on error message number errorNumber
		if errorNumber is not expectedNumber or message does not contain expectedText then
			set end of failures to theName & ": expected error " & expectedNumber & " containing “" & expectedText & "”, got " & errorNumber & ": " & message
		end if
	end try
end checkError

on display(theValue)
	try
		return theValue as text
	on error
		try
			{theValue} as «class XXXX»
		on error message
			return message
		end try
	end try
end display

on testDecodeValues()
	set config to soml's decode("# The edge service.
name: 'api-gateway'
replicas: 3
ratio: 0.5
enabled: true
owner: null
ports: [80, 443]
server: {
	host: 'localhost'
	port: 8080
}
'content-type': \"text/plain\\tutf-8\"
description:
	'''
	Line one.
	  Line two.
	'''")
	check("string", |name| of config, "api-gateway")
	check("int", replicas of config, 3)
	check("float", ratio of config, 0.5)
	check("bool", enabled of config, true)
	check("null", owner of config, missing value)
	check("array", ports of config, {80, 443})
	check("nested", |port| of server of config, 8080)
	check("quoted key and escape", |content-type| of config, "text/plain" & tab & "utf-8")
	check("block string", |description| of config, "Line one." & linefeed & "  Line two.")
	check("order", item 1 of item 1 of soml's entries(config), "name")
	check("array document", soml's decode("[1, 'two', 3.0, -infinity]"), {1, "two", 3.0, item 2 of soml's decode("[1, -infinity]")})
	check("float stays a real", class of (item 1 of soml's decode("[2.0]")), real)
	check("int stays an integer", class of (item 1 of soml's decode("[2]")), integer)
	check("largest integer", item 1 of soml's decode("[536870911, -536870912]"), 536870911)
	check("hex int", item 1 of soml's decode("[0xFF, 0o17, 0b101, 1_000]"), 255)
	check("exact float", item 1 of soml's decode("[0.1]"), 0.1)
	check("subnormal float", item 1 of soml's decode("[5e-324]") > 0, true)
	check("negative zero", item 1 of soml's decode("[-0.0]"), 0.0)
	check("keyword key", |true| of soml's decode("true: 1"), 1)
	check("deep nesting", class of soml's decode(my nestedArrays(100)), list)
	check("long line", count of (item 1 of soml's decode("[" & my repeatText("'x', ", 2000) & "]")), 1)
	check("many items", count of soml's decode("[" & my repeatText("1, ", 5000) & "]"), 5000)
	check("many keys", count of soml's entries(soml's decode(my manyKeys(300))), 300)
	check("emoji", item 1 of soml's decode("['😀é']"), "😀é")
	check("combining mark after line feed", item 2 of soml's decode("['a',
'" & (character id 769) & "b']"), (character id 769) & "b")
end testDecodeValues

on testDecodeErrors()
	try
		soml's decode("name: 'api'
port: 80a")
		set end of failures to "error: expected an error"
	on error message number errorNumber from details
		check("error number", errorNumber, 1)
		check("error message", message, "Invalid number “80a”. A string value must be quoted, as in '80a' at line 2, column 7")
		check("error line", |line| of details, 2)
		check("error column", |column| of details, 7)
		check("error reason", reason of details, "Invalid number “80a”. A string value must be quoted, as in '80a'")
	end try
	script errorCase1
		on run
			soml's decode("5")
		end run
	end script
	checkError("bare value", errorCase1, 1, "A bare value is not a document")
	script errorCase2
		on run
			soml's decode("a: [1 2]
b: '" & (character id 1) & "'")
		end run
	end script
	checkError("control character first", errorCase2, 1, "U+0001")
	script errorCase3
		on run
			soml's decode("a: 1e999
b: ]")
		end run
	end script
	checkError("float out of range before a later error", errorCase3, 1, "too large to be a finite float")
	script errorCase4
		on run
			soml's decode(my nestedArrays(101))
		end run
	end script
	checkError("deeper than 100", errorCase4, 1, "nested more than 100 levels")
	script errorCase5
		on run
			soml's decode("a: 1
'a': 2")
		end run
	end script
	checkError("duplicate key", errorCase5, 1, "Duplicate key a at line 2, column 1")
	script errorCase6
		on run
			soml's decode(5)
		end run
	end script
	checkError("not text", errorCase6, -1703, "expects text")
	script errorCase7
		on run
			soml's decode("\"a" & (character id 27) & "[31m\": 1
b")
		end run
	end script
	checkError("terminal escape in message", errorCase7, 1, "U+001B")
end testDecodeErrors

on testTaggedValues()
	set config to soml's decode("big: 9007199254740993
small: -9223372036854775808
mask: 0x7FFFFFFFFFFFFFFF
when: 2026-09-19T14:00:00.500+02:00
timeout: 90m
tiny: 1500ns
empty: {}
collide: {a: 1, A: 2}")
	check("big int", value of big of config, "9007199254740993")
	check("big int class", class of big of config, SOML int)
	check("smallest int", value of small of config, "-9223372036854775808")
	check("hex mask", value of mask of config, "9223372036854775807")
	check("instant", value of |when| of config, "2026-09-19T12:00:00.5Z")
	check("instant class", class of |when| of config, SOML instant)
	check("duration", value of |timeout| of config, "1h30m")
	check("duration class", class of |timeout| of config, SOML duration)
	check("small duration", value of tiny of config, "0.0000015s")
	check("empty object", |empty| of config, {class:SOML object, entries:{}})
	check("colliding keys", entries of collide of config, {{"a", 1}, {"A", 2}})
	check("empty document", soml's decode("{}"), {class:SOML object, entries:{}})
	-- A text that starts with U+FEFF would change in a record, so the objects are tagged.
	set fragile to soml's decode("a: '" & (character id 65279) & "x'
b: {c: 1}")
	check("fragile text keeps objects tagged", class of fragile, SOML object)
	check("fragile text value", id of item 2 of item 1 of entries of fragile, {65279, 120})
end testTaggedValues

on testKeyCase()
	-- AppleScript keeps one spelling of a label in a process. Once `KeyCase` is a label, `keycase` cannot be, so its object is tagged.
	set firstDecoded to soml's decode("KeyCase: 1")
	check("first spelling is a record", class of firstDecoded, record)
	set secondDecoded to soml's decode("keycase: 2
other: 3")
	check("second spelling is tagged", class of secondDecoded, SOML object)
	check("second spelling keeps its key", soml's entries(secondDecoded), {{"keycase", 2}, {"other", 3}})
	check("second spelling encodes exactly", soml's encode(secondDecoded), "keycase: 2" & linefeed & "other: 3" & linefeed)
	check("fromEntries with a kept spelling", class of soml's fromEntries({{"KeyCase", 1}}), record)
	check("fromEntries with another spelling", class of soml's fromEntries({{"KEYCASE", 1}}), SOML object)
	-- Keys that differ only in ASCII letter case in different objects tag only the object with the spelling that is not kept.
	set nested to soml's decode("'case-pair': {'Case-Pair': 1}")
	check("kept spelling stays a record", class of nested, record)
	check("other spelling is tagged", class of |case-pair| of nested, SOML object)
	-- The display of a record lowers the ASCII capitals of a label in bars that AppleScript made from text, but the record keeps them.
	set headers to soml's decode("headers: {Accept-Language: 'nb', 'X Tag': 1}
other: {Plain_Key: 2, 'lower-case': 3}")
	check("barred key with capitals is a record", class of |headers| of headers, record)
	check("barred key with capitals keeps its key", soml's entries(|headers| of headers), {{"Accept-Language", "nb"}, {"X Tag", 1}})
	check("identifier and lowercase barred keys", soml's entries(other of headers), {{"Plain_Key", 2}, {"lower-case", 3}})
	check("barred key with capitals encodes exactly", soml's encode(headers), "headers: {
	Accept-Language: 'nb'
	'X Tag': 1
}
other: {
	Plain_Key: 2
	lower-case: 3
}
")
	check("barred key with capitals sorts by its capitals", soml's encodeCanonical(soml's decode("b-key: 1
B-Key-Two: 2")), "B-Key-Two: 2" & linefeed & "b-key: 1" & linefeed)
	check("fromEntries with a barred key with capitals", soml's entries(soml's fromEntries({{"Accept-Encoding", 1}})), {{"Accept-Encoding", 1}})
	-- A capital that a combining mark follows, as in a decomposed “École”, which is how macOS names files.
	set decomposedKey to (character id {69, 769}) & "cole-file"
	check("barred key with a decomposed capital", soml's entries(soml's decode("'" & decomposedKey & "': 1")), {{decomposedKey, 1}})
	check("barred key with a decomposed capital encodes exactly", id of soml's encode(soml's decode("'" & decomposedKey & "': 1")), id of ("'" & decomposedKey & "': 1" & linefeed))
	check("record literal with a barred key with capitals",soml's encode({|Accept-Charset|:1}), "Accept-Charset: 1" & linefeed)
end testKeyCase

on testEncode()
	set config to {|name|:"api-gateway", replicas:3, ratio:0.5, enabled:true, owner:missing value, ports:{80, 443}, server:{host:"localhost", port:8080}}
	check("encode", soml's encode(config), "name: 'api-gateway'
replicas: 3
ratio: 0.5
enabled: true
owner: null
ports: [
	80
	443
]
server: {
	host: 'localhost'
	port: 8080
}
")
	check("canonical sorts keys", soml's encodeCanonical({b:1, a:{d:2, c:3}}), "a: {
	c: 3
	d: 2
}
b: 1
")
	check("keyword labels", soml's encode({name:"x", id:1, version:"2"}), "name: 'x'
id: 1
version: '2'
")
	check("multi-word keyword label", soml's encode({button returned:"OK"}), "'button returned': 'OK'
")
	check("array document", soml's encode({1, "a", {}, {}}), "[
	1
	'a'
	[]
	[]
]
")
	check("empty object", soml's encode({a:{class:SOML object, entries:{}}}), "a: {}
")
	check("strings", soml's encode({a:"it's", b:"tab" & tab, c:"C:\\path", d:"x" & (character id 1) & "y", e:"line" & linefeed & "two", f:"\"q\""}), "a: \"it's\"
b: \"tab\\t\"
c: 'C:\\path'
d: \"x\\u{1}y\"
e: \"line\\ntwo\"
f: '\"q\"'
")
	check("keys", soml's encode({|a b|:1, |404|:2, ||:3, |a.b|:4}), "'a b': 1
404: 2
'': 3
'a.b': 4
")
	check("floats", soml's encode({1.0, 0.1, 1.0E+21, 1.0E-7, 100.0, -0.0, 1.5E+300, 5.0E-324}), "[
	1.0
	0.1
	1e21
	1e-7
	100.0
	0.0
	1.5e300
	5e-324
]
")
	check("infinity", soml's encode(soml's decode("[infinity, -infinity]")), "[
	infinity
	-infinity
]
")
	check("integer beyond the literal range", soml's encode({536870911 + 536870911}), "[
	1073741822
]
")
	check("tagged values in any spelling", soml's encode({a:{class:SOML int, value:"0xFF"}, b:{class:SOML instant, value:"2026-09-19T14:00:00+02:00"}, c:{class:SOML duration, value:"90m"}}), "a: 255
b: 2026-09-19T12:00:00Z
c: 1h30m
")
	set theDate to current date
	set time of theDate to 0
	set encodedDate to soml's encode({theDate})
	check("date as an instant", encodedDate ends with "Z
]
", true)
	check("date round trip", soml's toDate(item 1 of soml's decode(encodedDate)), theDate)
	check("fragile text in encode", soml's encode({(character id 65279) & "x"}), "[
	'" & (character id 65279) & "x'
]
")
	set original to "service: {
	timeout: 1m30s
	retries: [1, 2.5, 'x']
	when: 2026-09-19T12:00:00Z
	big: 9223372036854775807
}
"
	check("round trip", soml's encodeCanonical(soml's decode(original)), "service: {
	big: 9223372036854775807
	retries: [
		1
		2.5
		'x'
	]
	timeout: 1m30s
	when: 2026-09-19T12:00:00Z
}
")
end testEncode

on testEncodeErrors()
	script errorCase8
		on run
			soml's encode("x")
		end run
	end script
	checkError("scalar root", errorCase8, 2, "A SOML document is an object or an array")
	script errorCase9
		on run
			soml's encode({a:"x" & return})
		end run
	end script
	checkError("carriage return", errorCase9, 2, "carriage return")
	script errorCase10
		on run
			soml's encode({a:me})
		end run
	end script
	checkError("script object", errorCase10, 2, "Cannot encode a script object at a")
	script errorCase11
		on run
			soml's encode({a:{class:"premium", b:1}})
		end run
	end script
	checkError("unknown class", errorCase11, 2, "Cannot encode a record of class premium at a")
	script errorCase12
		on run
			soml's encode({a:{class:SOML int, value:"0xff"}})
		end run
	end script
	checkError("invalid tagged int", errorCase12, 2, "Invalid SOML int at a")
	script errorCase13
		on run
			soml's encode({a:{class:SOML int, value:"9223372036854775808"}})
		end run
	end script
	checkError("int out of range", errorCase13, 2, "outside the 64-bit range")
	script errorCase14
		on run
			soml's encode({name:1, |name|:2})
		end run
	end script
	checkError("duplicate key", errorCase14, 2, "Duplicate key name")
	script errorCase15
		on run
			soml's encode(soml's decode(my nestedArrays(100)) & {})
			set deep to {}
			repeat 101 times
				set deep to {deep}
			end repeat
			soml's encode(deep)
		end run
	end script
	checkError("too deep", errorCase15, 2, "nested more than 100 levels deep")
end testEncodeErrors

on testEntries()
	check("entries", soml's entries({a:1, |b c|:{2}, name:"n"}), {{"a", 1}, {"b c", {2}}, {"name", "n"}})
	set made to soml's fromEntries({{"x y", 1}, {"z", {2, 3}}})
	check("fromEntries", |x y| of made, 1)
	check("fromEntries round trip", soml's entries(made), {{"x y", 1}, {"z", {2, 3}}})
	check("fromEntries empty", soml's fromEntries({}), {class:SOML object, entries:{}})
	check("fromEntries colliding", class of soml's fromEntries({{"q", 1}, {"Q", 2}}), SOML object)
	script errorCase16
		on run
			soml's fromEntries({{"q", 1}, {"q", 2}})
		end run
	end script
	checkError("fromEntries duplicate", errorCase16, 2, "Duplicate key q")
	script errorCase17
		on run
			soml's entries({1})
		end run
	end script
	checkError("entries of a list", errorCase17, -1703, "expects a record")
end testEntries

on testConversions()
	check("toNumber of an integer", soml's toNumber(5), 5)
	check("toNumber of a big int", soml's toNumber({class:SOML int, value:"9007199254740992"}), 9.007199254740992E+15)
	script errorCase18
		on run
			soml's toNumber({class:SOML int, value:"9007199254740993"})
		end run
	end script
	checkError("toNumber of an inexact int", errorCase18, 2, "cannot be represented exactly")
	check("toSeconds", soml's toSeconds({class:SOML duration, value:"1h30m0.5s"}), 5400.5)
	check("toSeconds negative", soml's toSeconds({class:SOML duration, value:"-1500ms"}), -1.5)
	set theDate to soml's toDate({class:SOML instant, value:"2024-07-01T12:00:00Z"})
	check("toDate", class of theDate, date)
	check("toDate value", soml's encode({theDate}), "[
	2024-07-01T12:00:00Z
]
")
	script errorCase19
		on run
			soml's toDate("2024-07-01T12:00:00Z")
		end run
	end script
	checkError("toDate of text", errorCase19, -1703, "expects a SOML instant")
end testConversions

on testDecodeFile()
	set directory to (current application's NSTemporaryDirectory() as text) & "soml-applescript-test-" & ((current application's NSUUID's UUID()'s UUIDString()) as text) & "/"
	current application's NSFileManager's defaultManager()'s createDirectoryAtPath:directory withIntermediateDirectories:true attributes:(missing value) |error|:(missing value)
	set thePath to directory & "config.soml"
	writeBytes(thePath, "name: 'é'
port: 8080
")
	check("decodeFile path", |port| of soml's decodeFile(thePath), 8080)
	check("decodeFile file", |name| of soml's decodeFile(thePath as POSIX file), "é")
	check("decodeFile alias", |port| of soml's decodeFile((thePath as POSIX file) as alias), 8080)
	set badPath to directory & "bad.soml"
	-- a: 'é' and then the byte 0xE9, which is not UTF-8.
	writeData(badPath, "YTogJ8Op6Sc=")
	try
		soml's decodeFile(badPath)
		set end of failures to "invalid UTF-8: expected an error"
	on error message number errorNumber
		check("invalid UTF-8", message, "Invalid UTF-8 byte 0xE9 at line 1, column 6")
	end try
	writeData(badPath, "77u/YTogMQ==")
	try
		soml's decodeFile(badPath)
		set end of failures to "BOM: expected an error"
	on error message
		check("BOM", message, "A byte order mark (BOM) is not allowed at line 1, column 1")
	end try
	script errorCase20
		on run
			soml's decodeFile("/nonexistent/config.soml")
		end run
	end script
	checkError("missing file", errorCase20, -43, "Could not read the file")
	current application's NSFileManager's defaultManager()'s removeItemAtPath:directory |error|:(missing value)
end testDecodeFile

on testInputEdgeCases()
	set directory to (current application's NSTemporaryDirectory() as text) & "soml-applescript-test-" & ((current application's NSUUID's UUID()'s UUIDString()) as text) & "/"
	current application's NSFileManager's defaultManager()'s createDirectoryAtPath:directory withIntermediateDirectories:true attributes:(missing value) |error|:(missing value)
	set thePath to directory & "file.soml"
	-- Foundation's decoder takes a stray 0xA9 as U+FFFD.
	checkFileError("stray 0xA9", thePath, "YTogIqkiCg==", "Invalid UTF-8 byte 0xA9 at line 1, column 5")
	checkFileError("first invalid UTF-8 sequence", thePath, "YTogIsO/qSIKYjogW/CPv79dCg==", "Invalid UTF-8 byte 0xA9 at line 1, column 6")
	checkFileError("truncated UTF-8", thePath, "YTog4oI=", "Incomplete UTF-8 sequence at the end of the input at line 1, column 4")
	checkFileError("byte order mark before a carriage return", thePath, "77u/YTogMQ0=", "A byte order mark (BOM) is not allowed at line 1, column 1")
	checkFileError("invalid UTF-8 after a byte order mark", thePath, "77u/YTog/w==", "Invalid UTF-8 byte 0xFF at line 1, column 5")
	checkFileError("U+FFFE at the start of a file", thePath, "77++YTogMQ==", "U+FFFE")
	current application's NSFileManager's defaultManager()'s removeItemAtPath:directory |error|:(missing value)
	check("byte order mark and combining mark at the start of a block string", id of item 1 of soml's decode("[
	'''
	" & (character id 65279) & (character id 769) & "x
	y
	'''
]"), {65279, 769, 120, 10, 121})
	script errorCase101
		on run
			soml's decode("a: 1" & my repeatText("0", 400))
		end run
	end script
	checkError("very long int", errorCase101, 1, "outside the 64-bit range")
	script errorCase102
		on run
			soml's decode("a: 1" & my repeatText("0", 400) & ".5")
		end run
	end script
	checkError("very long float", errorCase102, 1, "too large to be a finite float")
	script errorCase103
		on run
			soml's decode("a: 1
" & (character id 769) & "b: " & (character id 1))
		end run
	end script
	checkError("control character after a combining mark", errorCase103, 1, "at line 2, column 5")
	script errorCase104
		on run
			soml's decode("a: [1e999, !]")
		end run
	end script
	checkError("float before a later error in the first entry", errorCase104, 1, "too large to be a finite float. Use infinity if you mean it at line 1, column 5")
	script errorCase105
		on run
			soml's decode("\"a\" b: 1")
		end run
	end script
	checkError("quoted key and a word", errorCase105, 1, "Expected “:” after the key, but found “b” at line 1, column 5")
	script errorCase106
		on run
			soml's decode("a:
'b': 2")
		end run
	end script
	checkError("quoted key as a value", errorCase106, 1, "Expected a value, but found the key b at line 2, column 1")
	script errorCase107
		on run
			soml's encode({{class:SOML instant, value:"2026/01/01T00:00:00Z"}})
		end run
	end script
	checkError("instant with a malformed date", errorCase107, 2, "Invalid SOML instant at [0]")
	script errorCase108
		on run
			soml's entries({class:SOML object, foo:1})
		end run
	end script
	checkError("entries of a malformed SOML object", errorCase108, 2, "A SOML object is")
	script errorCase109
		on run
			soml's toNumber({class:SOML int, value:{"1", "2"}})
		end run
	end script
	checkError("toNumber with a value that is not text", errorCase109, -1703, "expects a SOML int")
	script errorCase110
		on run
			soml's encode({a:(current application's NSString's stringWithString:"x")})
		end run
	end script
	checkError("Objective-C object", errorCase110, 2, "Objective-C object")
	check("key that starts with a combining mark", soml's encode({class:SOML object, entries:{{(character id 769) & "x", 2}}}), "'" & (character id 769) & "x': 2
")
	check("string that starts with a combining mark", soml's encode({(character id 769) & "x"}), "[
	'" & (character id 769) & "x'
]
")
	set pairs to {}
	repeat with step from 1 to 3000
		set end of pairs to {"findings-key-" & step, step}
	end repeat
	check("fromEntries with many keys", count of soml's entries(soml's fromEntries(pairs)), 3000)
end testInputEdgeCases

on checkFileError(theName, thePath, base64Text, expectedText)
	if base64Text is not missing value then
		writeData(thePath, base64Text)
	end if
	set testCount to testCount + 1
	try
		soml's decodeFile(thePath)
		set end of failures to theName & ": expected an error"
	on error message number errorNumber
		if errorNumber is not 1 or message does not contain expectedText then
			set end of failures to theName & ": expected error 1 containing “" & expectedText & "”, got " & errorNumber & ": " & message
		end if
	end try
end checkFileError

on testLabelTable()
	-- AppleScript holds about 8,000 distinct record labels in a process. A document with more gives SOML objects.
	set parts to {}
	repeat with step from 1 to 9000
		set end of parts to "label-table-" & step & ": " & step
	end repeat
	set previousDelimiters to AppleScript's text item delimiters
	set AppleScript's text item delimiters to linefeed
	set theText to parts as text
	set AppleScript's text item delimiters to previousDelimiters
	set config to soml's decode(theText)
	check("label table overflow gives a SOML object", class of config, SOML object)
	check("label table overflow keeps every key", count of entries of config, 9000)
	set pairs to {}
	repeat with step from 1 to 9000
		set end of pairs to {"label-table-entry-" & step, step}
	end repeat
	check("fromEntries without room for labels", class of soml's fromEntries(pairs), SOML object)
end testLabelTable

on testValueEdgeCases()
	script errorCase201
		on run
			soml's encode({a:{class:real, b:1}})
		end run
	end script
	checkError("record with a built-in class", errorCase201, 2, "Cannot encode a record of class real at a")
	script errorCase202
		on run
			soml's encode({a:{class:text, b:1}})
		end run
	end script
	checkError("record with the class text", errorCase202, 2, "Cannot encode a record of class text at a")
	script errorCase203
		on run
			soml's encode(soml's fromEntries({{"", {x:me}}}))
		end run
	end script
	checkError("path with an empty key", errorCase203, 2, "at ''.x")
	script errorCase204
		on run
			soml's toNumber({class:SOML int, value:"abc"})
		end run
	end script
	checkError("toNumber of an invalid int", errorCase204, -1703, "toNumber() got an invalid value")
	script errorCase205
		on run
			soml's toSeconds({class:SOML duration, value:"1d"})
		end run
	end script
	checkError("toSeconds of an invalid duration", errorCase205, -1703, "there is no day unit")
	set pairs to {}
	repeat with step from 1 to 4001
		set end of pairs to {"budget-key-" & step, step}
	end repeat
	check("fromEntries with more keys than the budget", class of soml's fromEntries(pairs), SOML object)
	set lone to ((current application's NSString's stringWithString:(character id 128512))'s substringToIndex:1) as text
	script errorCase206
		on run
			soml's decode("a: 1 # " & lone)
		end run
	end script
	checkError("lone surrogate in a comment", errorCase206, 1, "A lone surrogate (U+D83D) is not a Unicode scalar value at line 1, column 8")
	script errorCase207
		on run
			soml's decode("a: '" & lone & "'")
		end run
	end script
	checkError("lone surrogate in a string", errorCase207, 1, "A lone surrogate (U+D83D) is not a Unicode scalar value at line 1, column 5")
	-- An invalid byte after many multibyte characters is found in linear time.
	set directory to (current application's NSTemporaryDirectory() as text) & "soml-applescript-test-" & ((current application's NSUUID's UUID()'s UUIDString()) as text) & "/"
	current application's NSFileManager's defaultManager()'s createDirectoryAtPath:directory withIntermediateDirectories:true attributes:(missing value) |error|:(missing value)
	set thePath to directory & "multibyte.soml"
	set theData to (current application's NSString's stringWithString:("a: '" & my repeatText("é", 20000) & "'" & linefeed))'s dataUsingEncoding:(current application's NSUTF8StringEncoding)
	set theData to theData's mutableCopy()
	theData's appendData:(current application's NSData's alloc()'s initWithBase64EncodedString:"/w==" options:0)
	theData's writeToFile:thePath atomically:true
	set startTime to current application's NSDate's timeIntervalSinceReferenceDate()
	checkFileError("invalid byte after multibyte characters", thePath, missing value, "Invalid UTF-8 byte 0xFF at line 2, column 1")
	check("invalid byte after multibyte characters is fast", ((current application's NSDate's timeIntervalSinceReferenceDate()) - startTime) < 10, true)
	current application's NSFileManager's defaultManager()'s removeItemAtPath:directory |error|:(missing value)
	-- Many escapes are read in linear time.
	set parts to {}
	repeat with step from 1 to 3000
		set end of parts to "line " & step & tab & "\\"
	end repeat
	set previousDelimiters to AppleScript's text item delimiters
	set AppleScript's text item delimiters to linefeed
	set blob to parts as text
	set AppleScript's text item delimiters to previousDelimiters
	set startTime to current application's NSDate's timeIntervalSinceReferenceDate()
	check("string with many escapes", |payload| of soml's decode(soml's encode({payload:blob})) = blob, true)
	check("string with many escapes is fast", ((current application's NSDate's timeIntervalSinceReferenceDate()) - startTime) < 15, true)
	set pairs to {}
	repeat with step from 1 to 5000
		set end of pairs to {"sorted-key-" & step, step}
	end repeat
	script errorCase208
		on run
			soml's fromEntries(pairs & {{"sorted-key-4000", 0}})
		end run
	end script
	checkError("duplicate among many keys", errorCase208, 2, "Duplicate key sorted-key-4000")
	check("keys that differ in case among many keys", count of entries of soml's fromEntries(pairs & {{"SORTED-KEY-4000", 0}}), 5001)
end testValueEdgeCases

on testCallerState()
	set AppleScript's text item delimiters to "|"
	soml's decode("a: [1, 2]
b: '''
	x
	'''")
	soml's encode({a:{1, 2}})
	check("text item delimiters are kept", AppleScript's text item delimiters as text, "|")
	set AppleScript's text item delimiters to ""
	considering case
		ignoring white space, punctuation and hyphens
			set config to soml's decode("a-b: 'x y'
c: [1, 2]")
		end ignoring
	end considering
	check("considering and ignoring do not change the result", |a-b| of config, "x y")
end testCallerState

on writeBytes(thePath, theText)
	(current application's NSString's stringWithString:theText)'s writeToFile:thePath atomically:true encoding:(current application's NSUTF8StringEncoding) |error|:(missing value)
end writeBytes

on writeData(thePath, base64Text)
	set theData to current application's NSData's alloc()'s initWithBase64EncodedString:base64Text options:0
	theData's writeToFile:thePath atomically:true
end writeData

on nestedArrays(depth)
	return repeatText("[", depth) & repeatText("]", depth)
end nestedArrays

on repeatText(theText, theCount)
	set parts to {}
	repeat theCount times
		set end of parts to theText
	end repeat
	set previousDelimiters to AppleScript's text item delimiters
	set AppleScript's text item delimiters to ""
	set joined to parts as text
	set AppleScript's text item delimiters to previousDelimiters
	return joined
end repeatText

on manyKeys(theCount)
	set parts to {}
	repeat with step from 1 to theCount
		set end of parts to "key" & step & ": " & step
	end repeat
	set previousDelimiters to AppleScript's text item delimiters
	set AppleScript's text item delimiters to linefeed
	set joined to parts as text
	set AppleScript's text item delimiters to previousDelimiters
	return joined
end manyKeys
