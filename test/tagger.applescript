(*
Decodes and encodes each file listed in a file, and writes one JSON line for each to an output file, for `conformance.js`:

	{"file": …, "ok": true, "value": <tagged>, "canonical": …, "ordered": …, "roundTrip": …}
	{"file": …, "ok": false, "message": …, "number": …, "line": …, "column": …}

	OSA_LIBRARY_PATH=build osascript test/tagger.applescript list.txt output.jsonl

The tagged value is the suite's tagged JSON, except that a duration is {"type": "duration", "canonical": …}, which `conformance.js` converts to nanoseconds.
*)

use AppleScript version "2.8"
use framework "Foundation"
use framework "JavaScriptCore"
use scripting additions
use soml : script "SOML"

property javaScriptContext : missing value

on run {listPath, outputPath}
	set javaScriptContext to current application's JSContext's new()
	set listText to (current application's NSString's stringWithContentsOfFile:listPath encoding:(current application's NSUTF8StringEncoding) |error|:(missing value)) as text
	set previousDelimiters to AppleScript's text item delimiters
	set AppleScript's text item delimiters to linefeed
	set thePaths to text items of listText
	set AppleScript's text item delimiters to previousDelimiters
	script Store
		property outputLines : {}
	end script
	repeat with thePath in thePaths
		set thePath to contents of thePath
		if thePath is not "" then
			set end of Store's outputLines to my processFile(thePath)
		end if
	end repeat
	set AppleScript's text item delimiters to linefeed
	set outputText to (Store's outputLines as text) & linefeed
	set AppleScript's text item delimiters to previousDelimiters
	(current application's NSString's stringWithString:outputText)'s writeToFile:outputPath atomically:true encoding:(current application's NSUTF8StringEncoding) |error|:(missing value)
end run

on processFile(thePath)
	try
		set theValue to soml's decodeFile(thePath)
	on error message number errorNumber from details
		set lineNumber to "null"
		set columnNumber to "null"
		try
			set lineNumber to (|line| of details) as text
			set columnNumber to (|column| of details) as text
		end try
		return "{\"file\":" & jsonString(thePath) & ",\"ok\":false,\"message\":" & jsonString(message) & ",\"number\":" & errorNumber & ",\"line\":" & lineNumber & ",\"column\":" & columnNumber & "}"
	end try
	try
		set tagged to tag(theValue)
		set canonical to soml's encodeCanonical(theValue)
		set ordered to soml's encode(theValue)
		set roundTrip to soml's encodeCanonical(soml's decode(ordered))
	on error message number errorNumber
		return "{\"file\":" & jsonString(thePath) & ",\"ok\":true,\"writeError\":" & jsonString(message & " (" & errorNumber & ")") & "}"
	end try
	return "{\"file\":" & jsonString(thePath) & ",\"ok\":true,\"value\":" & tagged & ",\"canonical\":" & jsonString(canonical) & ",\"ordered\":" & jsonString(ordered) & ",\"roundTrip\":" & jsonString(roundTrip) & "}"
end processFile

on tag(theValue)
	set theClass to class of theValue
	if theClass is list then
		set parts to {}
		repeat with theItem in theValue
			set end of parts to tag(contents of theItem)
		end repeat
		return "[" & joinTexts(parts, ",") & "]"
	end if
	if theClass is record or theClass is in {«class SOMi», «class SOMc», «class SOMt», «class SOMd», «class SOMo»} then
		if theClass is «class SOMi» then
			return "{\"type\":\"int\",\"value\":" & jsonString(value of theValue) & "}"
		else if theClass is «class SOMc» then
			return "{\"type\":\"date\",\"value\":" & jsonString(value of theValue) & "}"
		else if theClass is «class SOMt» then
			return "{\"type\":\"instant\",\"value\":" & jsonString(value of theValue) & "}"
		else if theClass is «class SOMd» then
			return "{\"type\":\"duration\",\"canonical\":" & jsonString(value of theValue) & "}"
		end if
		set parts to {}
		repeat with theEntry in soml's entries(theValue)
			set end of parts to jsonString(item 1 of theEntry) & ":" & tag(item 2 of theEntry)
		end repeat
		return "{" & joinTexts(parts, ",") & "}"
	end if
	if theClass is text then
		return "{\"type\":\"string\",\"value\":" & jsonString(theValue) & "}"
	else if theClass is integer then
		return "{\"type\":\"int\",\"value\":\"" & (theValue as text) & "\"}"
	else if theClass is real then
		javaScriptContext's setObject:{theValue} forKeyedSubscript:"x"
		set formatted to ((javaScriptContext's evaluateScript:"(() => { const v = x[0]; if (v === Infinity) return 'infinity'; if (v === -Infinity) return '-infinity'; if (v === 0) return '0.0'; const t = String(v).replace('e+', 'e'); return /[.e]/.test(t) ? t : t + '.0'; })()")'s toString()) as text
		return "{\"type\":\"float\",\"value\":\"" & formatted & "\"}"
	else if theClass is boolean then
		if theValue then
			return "{\"type\":\"bool\",\"value\":\"true\"}"
		end if
		return "{\"type\":\"bool\",\"value\":\"false\"}"
	else if theValue is missing value then
		return "{\"type\":\"null\",\"value\":\"null\"}"
	end if
	error "Unexpected value of class " & (theClass as text)
end tag

on jsonString(theText)
	set theCodes to id of theText
	if class of theCodes is integer then
		set theCodes to {theCodes}
	end if
	script Store
		property source : theCodes
		property parts : {}
	end script
	repeat with step from 1 to count Store's source
		set theCode to item step of Store's source
		if theCode = 34 then
			set end of Store's parts to "\\\""
		else if theCode = 92 then
			set end of Store's parts to "\\\\"
		else if theCode < 32 or theCode = 127 then
			set hexDigits to "0123456789abcdef"
			set end of Store's parts to "\\u00" & character (theCode div 16 + 1) of hexDigits & character (theCode mod 16 + 1) of hexDigits
		else
			set end of Store's parts to character id theCode
		end if
	end repeat
	return "\"" & joinTexts(Store's parts, "") & "\""
end jsonString

(*
Joins texts. A list of two or more texts as text loses a U+FEFF at the start of the result, so then the texts are joined after a line feed, which is removed again.
*)
on joinTexts(theTexts, theDelimiter)
	set previousDelimiters to AppleScript's text item delimiters
	set AppleScript's text item delimiters to theDelimiter
	set isFragile to false
	if (count theTexts) > 1 and length of item 1 of theTexts > 0 then
		set isFragile to (id of text 1 thru 1 of item 1 of theTexts) is 65279
	end if
	if isFragile then
		set joined to ({linefeed} & theTexts) as text
		set joined to text (2 + (length of theDelimiter)) thru -1 of joined
	else
		set joined to theTexts as text
	end if
	set AppleScript's text item delimiters to previousDelimiters
	return joined
end joinTexts
