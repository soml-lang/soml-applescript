(*
SOML for AppleScript

Read and write SOML, a config format for humans: https://soml.sh

	use soml : script "SOML"

	set config to soml's decodeFile("/path/to/config.soml")
	set thePort to |port| of |server| of config
	set theText to soml's encode(config)

Values:

	object    record with the keys as labels, in document order
	array     list
	string    text
	int       integer, or {class:SOML int, value:"9007199254740993"} outside -536870912 to 536870911
	float     real, including infinity and -infinity
	bool      boolean
	null      missing value
	date      {class:SOML date, value:"2027-09-19"}
	instant   {class:SOML instant, value:"2026-09-19T12:00:00Z"}
	duration  {class:SOML duration, value:"1h30m"}

An object that a record cannot hold exactly is {class:SOML object, entries:{{key, value}, …}}: an empty object, an object with two keys that differ only in ASCII letter case, an object with a key that AppleScript spells differently because it kept another spelling of the label earlier in the process, and every object of a document whose native labels AppleScript cannot expose, with more than 4,000 distinct keys, or with a text that starts with U+FEFF or U+FFFE.

The classes SOML int, SOML date, SOML instant, SOML duration, and SOML object are the terminology of this library. Without it, they are «class SOMi», «class SOMc», «class SOMt», «class SOMd», and «class SOMo».
*)

use AppleScript version "2.8"
use framework "Foundation"
use framework "JavaScriptCore"
use scripting additions

-- The error numbers, for `on error number`.
property invalidDocumentErrorNumber : 1
property unsupportedValueErrorNumber : 2
property wrongTypeErrorNumber : -1703

property maximumDepth : 100

-- AppleScript holds about 8,000 distinct record labels in a process, and once that table is full, even AppleScriptObjC calls fail. A document or `fromEntries()` with more distinct keys than this gives tagged objects, so that one call cannot fill the table.
property maximumDistinctKeys : 4000

-- Names for the characters that are invisible or easy to mistake, from the reference implementation, so an error can say what it found.
property characterNames : {{1564, "ARABIC LETTER MARK"}, {133, "NEXT LINE"}, {160, "NO-BREAK SPACE"}, {173, "SOFT HYPHEN"}, {5760, "OGHAM SPACE MARK"}, {8192, "EN QUAD"}, {8193, "EM QUAD"}, {8194, "EN SPACE"}, {8195, "EM SPACE"}, {8196, "THREE-PER-EM SPACE"}, {8197, "FOUR-PER-EM SPACE"}, {8198, "SIX-PER-EM SPACE"}, {8199, "FIGURE SPACE"}, {8200, "PUNCTUATION SPACE"}, {8201, "THIN SPACE"}, {8202, "HAIR SPACE"}, {8203, "ZERO WIDTH SPACE"}, {8204, "ZERO WIDTH NON-JOINER"}, {8205, "ZERO WIDTH JOINER"}, {8206, "LEFT-TO-RIGHT MARK"}, {8207, "RIGHT-TO-LEFT MARK"}, {8232, "LINE SEPARATOR"}, {8233, "PARAGRAPH SEPARATOR"}, {8234, "LEFT-TO-RIGHT EMBEDDING"}, {8235, "RIGHT-TO-LEFT EMBEDDING"}, {8236, "POP DIRECTIONAL FORMATTING"}, {8237, "LEFT-TO-RIGHT OVERRIDE"}, {8238, "RIGHT-TO-LEFT OVERRIDE"}, {8239, "NARROW NO-BREAK SPACE"}, {8287, "MEDIUM MATHEMATICAL SPACE"}, {8288, "WORD JOINER"}, {8294, "LEFT-TO-RIGHT ISOLATE"}, {8295, "RIGHT-TO-LEFT ISOLATE"}, {8296, "FIRST STRONG ISOLATE"}, {8297, "POP DIRECTIONAL ISOLATE"}, {12288, "IDEOGRAPHIC SPACE"}, {65279, "ZERO WIDTH NO-BREAK SPACE"}}
-- The named characters that are whitespace in Unicode, and U+200B and U+FEFF, whose names call them spaces.
property namedWhitespace : {133, 160, 5760, 8192, 8193, 8194, 8195, 8196, 8197, 8198, 8199, 8200, 8201, 8202, 8203, 8232, 8233, 8239, 8287, 12288, 65279}

-- AppleScript integers are 30-bit in literals and coercions.
property smallestInteger : -536870912
property largestInteger : 536870911

-- Native text checks and numeric conversion objects are created only when needed.
property documentLineBreakExpression : missing value
property documentControlCharacters : missing value
property nonBareKeyCharacters : missing value
property nonLiteralStringCharacters : missing value
property stringControlExpression : missing value
property terminalCharacters : missing value
property cachedJavaScriptContext : missing value

-- Floats are converted by JavaScriptCore, which is exact, where AppleScript's own conversions are rounded and use the locale.
property floatScript : "(function (texts) {
	return texts.map(text => {
		const value = Number(text);
		if (!Number.isFinite(value)) {
			return 'infinite';
		}
		if (value === 0) {
			return /[1-9]/.test(text.split('e')[0]) ? 'zero' : 0;
		}
		return value;
	});
})"

property floatFormatScript : "(function (values) {
	return values.map(value => {
		if (Number.isNaN(value)) {
			return '';
		}
		if (value === Infinity) {
			return 'infinity';
		}
		if (value === -Infinity) {
			return '-infinity';
		}
		const text = String(value).replace('e+', 'e');
		return /[.e]/.test(text) ? text : text + '.0';
	});
})"

(*
Read a SOML document from text. Returns a record, a list, or a tagged object, because a document is always an object or an array.
*)
on decode(theText)
	if not my isTextValue(theText) then
		error "decode() expects text, but got " & my describeClass(theText) & "." number wrongTypeErrorNumber
	end if
	return my decodeText(theText)
end decode

(*
Read a SOML document from a file, given as a POSIX path, a file, or an alias. The file must be UTF-8, and invalid UTF-8 is an error at its position, rather than being replaced.
*)
on decodeFile(theFile)
	set thePath to my posixPath(theFile)
	-- Prefixing keeps leading U+FEFF or U+FFFE intact through the text bridge, then the prefix is removed natively.
	set nativePath to my nativeString(thePath)
	set {theData, readError} to current application's NSData's dataWithContentsOfFile:nativePath options:0 |error|:(reference)
	if theData is missing value then
		error my sanitize("Could not read the file " & thePath & ": " & ((readError's localizedDescription()) as text)) number -43
	end if
	-- `NSString` drops a byte order mark, so it is checked in the bytes.
	set hasByteOrderMark to false
	set contentData to theData
	if (theData's |length|()) ≥ 3 then
		set hasByteOrderMark to my bytesOf(theData, 0, 3) = {239, 187, 191}
		if hasByteOrderMark then
			set contentData to theData's subdataWithRange:{location:3, |length|:(theData's |length|()) - 3}
		end if
	end if
	set theString to current application's NSString's alloc()'s initWithData:theData encoding:(current application's NSUTF8StringEncoding)
	-- Foundation's decoder accepts a few invalid bytes, such as a stray 0xA9, as U+FFFD, so the text must give back the same bytes.
	if theString is missing value then
		my failInvalidUTF8(theData)
	end if
	if not ((theString's dataUsingEncoding:(current application's NSUTF8StringEncoding))'s isEqualToData:contentData) then
		my failInvalidUTF8(theData)
	end if
	if hasByteOrderMark then
		error "A byte order mark (BOM) is not allowed at line 1, column 1" number invalidDocumentErrorNumber from {reason:"A byte order mark (BOM) is not allowed", |line|:1, |column|:1}
	end if
	return my decodeText(my textOfString(theString))
end decodeFile

(*
Write a value as a SOML document, keeping the order of record labels.
*)
on encode(theValue)
	return my encodeValue(theValue, false)
end encode

(*
Write a value as a SOML document in canonical form: object keys sorted, so equal values give equal text, for hashing and comparing.
*)
on encodeCanonical(theValue)
	return my encodeValue(theValue, true)
end encodeCanonical

(*
The keys and values of a record or a tagged object, in order: {{key, value}, …}. AppleScript cannot list the labels of a record by itself.
*)
on entries(theValue)
	if class of theValue is not record and class of theValue is not «class SOMo» then
		error "entries() expects a record, but got " & my describeClass(theValue) & "." number wrongTypeErrorNumber
	end if
	set theValue to my resolveReference(theValue)
	set theWriter to my makeWriter(theValue, false)
	return theWriter's recordEntries(theValue)
end entries

(*
A record with the given keys and values: {{key, value}, …}. Gives {class:SOML object, entries:…} where a record cannot hold or expose the entries exactly: for an empty list, keys that differ only in ASCII letter case or that AppleScript spells differently, more than `maximumDistinctKeys` keys, some opaque values, and values that an Apple event changes or cannot take. Errors with number 2 for a duplicate key, and -1703 for a list that is not of {key, value} lists.
*)
on fromEntries(theEntries)
	if not my isListValue(theEntries) then
		error "fromEntries() expects a list of {key, value} lists, but got " & my describeClass(theEntries) & "." number wrongTypeErrorNumber
	end if
	set theEntries to my resolveReference(theEntries)
	script Store
		property pairs : theEntries
		property pairCount : count theEntries
		property currentPair : missing value
		property fields : {}
		property keys : {}
		property probeFields : {}
		property folded : {}
		property exact : {}
		property order : {}
	end script
	if Store's pairCount = 0 then
		return {class:«class SOMo», entries:{}}
	end if
	set collides to false
	set hasCapitals to false
	set exactKeys to missing value
	if Store's pairCount > my maximumDistinctKeys then
		set exactKeys to current application's NSMutableSet's |set|()
	end if
	repeat with theIndex from 1 to Store's pairCount
		set Store's currentPair to item theIndex of Store's pairs
		-- A record may report class list while its items cannot be read.
		try
			if class of Store's currentPair is not list or (count Store's currentPair) is not 2 or not my isTextValue(item 1 of Store's currentPair) then
				error number wrongTypeErrorNumber
			end if
		on error number errorNumber
			if errorNumber is -128 then
				error number -128
			end if
			error "fromEntries() expects a list of {key, value} lists with text keys, but item " & theIndex & " is " & my describeClass(Store's currentPair) & "." number wrongTypeErrorNumber
		end try
		set theKey to item 1 of Store's currentPair
		if exactKeys is not missing value then
			-- Prefixing preserves leading U+FEFF or U+FFFE through the native text bridge. Above the record limit, only exact duplicate detection is needed, without codepoint arrays or sorting.
			set exactKey to "x" & theKey
			if (exactKeys's containsObject:exactKey) as boolean then
				error my sanitize("Duplicate key " & my describeKey(theKey) & " in fromEntries().") number unsupportedValueErrorNumber
			end if
			exactKeys's addObject:exactKey
		else
			set keyCodes to my codePoints(theKey)
			set foldedCodes to my foldCase(keyCodes)
			if not hasCapitals then
				set hasCapitals to keyCodes is not foldedCodes
			end if
			-- `contains` compares the code points natively, which is much faster than a loop. Many keys are sorted instead, below.
			if Store's pairCount ≤ 256 then
				if Store's folded contains {foldedCodes} then
					if Store's exact contains {keyCodes} then
						error my sanitize("Duplicate key " & my describeKey(theKey) & " in fromEntries().") number unsupportedValueErrorNumber
					end if
					set collides to true
				end if
			end if
			set end of Store's folded to foldedCodes
			set end of Store's exact to keyCodes
		end if
	end repeat
	if Store's pairCount > my maximumDistinctKeys then
		return {class:«class SOMo», entries:Store's pairs}
	end if
	if Store's pairCount > 256 then
		-- Exact duplicates are adjacent in their own order, so even a large group of case variants needs no pairwise scan.
		set Store's order to my sortedCodeOrder(Store's exact)
		repeat with step from 2 to count Store's order
			set previousIndex to item (step - 1) of Store's order
			set currentIndex to item step of Store's order
			if item previousIndex of Store's exact = item currentIndex of Store's exact then
				error my sanitize("Duplicate key " & my describeKey(item 1 of item currentIndex of Store's pairs) & " in fromEntries().") number unsupportedValueErrorNumber
			end if
		end repeat
		-- Keys that are the same ignoring ASCII letter case are next to each other in the sorted order.
		if hasCapitals then
			set Store's order to my sortedCodeOrder(Store's folded)
			repeat with step from 2 to count Store's order
				if item (item step of Store's order) of Store's folded = item (item (step - 1) of Store's order) of Store's folded then
					set collides to true
					exit repeat
				end if
			end repeat
		end if
	end if
	if collides then
		return {class:«class SOMo», entries:Store's pairs}
	end if
	-- A record of the keys, including nested record labels, shows the spelling that AppleScript keeps for each.
	try
		set nestedKeys to my keysForNativeRecord(Store's pairs)
		if nestedKeys is missing value then
			return {class:«class SOMo», entries:Store's pairs}
		end if
		repeat with theIndex from 1 to Store's pairCount
			set keyText to item 1 of item theIndex of Store's pairs
			set end of Store's keys to keyText
			set end of Store's fields to keyText
			set end of Store's fields to item 2 of item theIndex of Store's pairs
		end repeat
		if nestedKeys is not {} then
			repeat with theKey in nestedKeys
				set end of Store's keys to contents of theKey
			end repeat
			-- A label reused in many nested records needs only one exact spelling probe.
			set Store's keys to ((current application's NSOrderedSet's orderedSetWithArray:(Store's keys))'s array()) as list
		end if
		repeat with theKey in Store's keys
			set end of Store's probeFields to contents of theKey
			set end of Store's probeFields to 0
		end repeat
		set {probeRecord, theRecord} to my materializeRecords({{«class usrf»:Store's probeFields}, {«class usrf»:Store's fields}})
	on error number errorNumber
		-- An Apple event cannot take every value, such as a script object, and AppleScript holds about 8,000 distinct labels in a process. The entries are kept as they are then.
		if errorNumber is -128 then
			error number -128
		end if
		return {class:«class SOMo», entries:Store's pairs}
	end try
	if my respelledKeys(probeRecord, Store's keys) is not {} then
		return {class:«class SOMo», entries:Store's pairs}
	end if
	return theRecord
end fromEntries

(*
A SOML int as an AppleScript number: an integer as it is, or a tagged int as a real when it is exact, which it is up to 2^53.
*)
on toNumber(theValue)
	if my hasScalarShape(theValue, integer) then
		return my resolveReference(theValue)
	end if
	set theText to my taggedText(theValue, «class SOMi», "toNumber()")
	set theReader to my makeReader("")
	try
		set theNumber to theReader's parseTaggedInt(theText)
	on error reason number errorNumber
		my failTagged("toNumber()", reason, errorNumber)
	end try
	if class of theNumber is integer then
		return theNumber
	end if
	set digitCodes to my codePoints(value of theNumber)
	set isNegative to item 1 of digitCodes = 45
	if isNegative then
		set digitCodes to rest of digitCodes
	end if
	-- 2^53 = 9007199254740992.
	if (count digitCodes) > 16 or ((count digitCodes) = 16 and my compareCodes(digitCodes, id of "9007199254740992") > 0) then
		error "The int " & (value of theNumber) & " cannot be represented exactly as an AppleScript number." number unsupportedValueErrorNumber
	end if
	set theReal to my digitsValue(digitCodes)
	if isNegative then
		return -theReal
	end if
	return theReal
end toNumber

(*
A SOML instant as an AppleScript date, in local time. A date holds whole seconds, so a fraction of a second is dropped.
*)
on toDate(theValue)
	set theText to my taggedText(theValue, «class SOMt», "toDate()")
	set theReader to my makeReader("")
	try
		set epochSeconds to theReader's instantEpochSeconds(theText)
	on error reason number errorNumber
		my failTagged("toDate()", reason, errorNumber)
	end try
	return (current application's NSDate's dateWithTimeIntervalSince1970:epochSeconds) as date
end toDate

(*
A SOML duration as a number of seconds, a real. It is exact up to about 104 days, and rounded beyond that.
*)
on toSeconds(theValue)
	set theText to my taggedText(theValue, «class SOMd», "toSeconds()")
	try
		set {theSeconds, theNanoseconds, isNegative} to my durationParts(theText)
	on error reason number errorNumber
		my failTagged("toSeconds()", reason, errorNumber)
	end try
	set total to theSeconds + theNanoseconds / 1.0E+9
	if isNegative then
		return -total
	end if
	return total
end toSeconds

-- Private

(*
Resolves a reference passed as a public argument. A reference compares as its object specifier, rather than its target value. Comparing the coercion result with the original keeps a singleton list that can also coerce to a reference.
*)
on resolveReference(theValue)
	try
		set theReference to theValue as reference
	on error number -1700
		return theValue
	end try
	if theReference is not theValue then
		return theValue
	end if
	return contents of theReference
end resolveReference

-- Reads a document, and turns the reader's errors into errors with a line and a column, with the errors that apply to every character first.
on decodeText(theText)
	set theReader to my makeReader(theText)
	try
		return theReader's readDocument()
	on error message number errorNumber from details
		if errorNumber is not invalidDocumentErrorNumber or class of details is not list then
			error message number errorNumber from details
		end if
		set {reason, lineIndex, position} to theReader's prioritize(details)
		set {lineNumber, columnNumber} to theReader's locate(lineIndex, position)
		set reason to my sanitize(reason)
		error reason & " at line " & lineNumber & ", column " & columnNumber number invalidDocumentErrorNumber from {reason:reason, |line|:lineNumber, |column|:columnNumber}
	end try
end decodeText

(*
Splits text at a delimiter, such as a line feed. A text item delimiter does not split at a line feed that a combining mark follows, so a piece may hold a line feed of its own.
*)
on splitText(theText, theDelimiter)
	set previousDelimiters to AppleScript's text item delimiters
	try
		considering case, diacriticals, hyphens, punctuation and white space
			set AppleScript's text item delimiters to theDelimiter
			set thePieces to text items of theText
		end considering
	on error message number errorNumber
		set AppleScript's text item delimiters to previousDelimiters
		error message number errorNumber
	end try
	set AppleScript's text item delimiters to previousDelimiters
	return thePieces
end splitText

(*
Joins texts. A list of two or more texts as text loses a U+FEFF at the start of the result, so when the first text that is not empty starts with one, the texts are joined after a line feed, which is removed again.
*)
on joinTexts(theTexts, theDelimiter)
	if theTexts = {} then
		return ""
	end if
	if (count theTexts) = 1 then
		return item 1 of theTexts
	end if
	set previousDelimiters to AppleScript's text item delimiters
	-- The first text that is not empty decides.
	set isFragile to false
	repeat with theText in theTexts
		if length of theText > 0 then
			set isFragile to item 1 of codePoints(text 1 thru 1 of theText) is 65279
			exit repeat
		end if
	end repeat
	try
		set AppleScript's text item delimiters to theDelimiter
		if isFragile then
			set joined to ({linefeed} & theTexts) as text
			set joined to text (2 + (length of theDelimiter)) thru -1 of joined
		else
			set joined to theTexts as text
		end if
	on error message number errorNumber
		set AppleScript's text item delimiters to previousDelimiters
		error message number errorNumber
	end try
	set AppleScript's text item delimiters to previousDelimiters
	return joined
end joinTexts

(*
The Unicode scalar values of text, as a list. `id of` takes time quadratic in the length of the text, so long text is split in halves first.
*)
on codePoints(theText)
	set theLength to length of theText
	if theLength > 512 then
		set middleIndex to theLength div 2
		return codePoints(text 1 thru middleIndex of theText) & codePoints(text (middleIndex + 1) thru theLength of theText)
	end if
	return (id of theText) as list
end codePoints

(*
Whether text starts with a byte-order character that changes during AppleScriptObjC or Apple event conversion.
*)
on hasByteOrderPrefix(theText)
	return length of theText > 0 and item 1 of ((id of text 1 thru 1 of theText) as list) is in {65279, 65534}
end hasByteOrderPrefix

(*
An NSString with every leading U+FEFF and U+FFFE preserved through the text bridge.
*)
on nativeString(theText)
	return (current application's NSString's stringWithString:("x" & theText))'s substringFromIndex:1
end nativeString

(*
Nested record labels to include in a native record's key probe. Returns missing value for opaque values or anything an Apple event changes: raw Unicode data, a record whose class claims to be another type or is explicit record metadata, a text that starts with U+FEFF or U+FFFE, or an integer outside -536870912 to 536870911. Checks every value before bridging records to read their labels.
*)
on keysForNativeRecord(theValue)
	script Store
		property pending : {theValue}
		property current : missing value
		property keys : {}
		property nativeRecords : {}
	end script
	-- A queue that is read by index, because removing an item copies a list.
	set nextIndex to 1
	repeat while nextIndex ≤ (count Store's pending)
		set Store's current to item nextIndex of Store's pending
		set item nextIndex of Store's pending to missing value
		set nextIndex to nextIndex + 1
		set theClass to class of Store's current
		if theClass is in {integer, real, boolean, date} then
			-- A scalar becomes a one-item list; a record exposes its fields even when its class claims to be a scalar.
			if not my hasScalarShape(Store's current, theClass) then
				return missing value
			end if
		end if
		if theClass is text then
			if not my isTextValue(Store's current) then
				return missing value
			end if
			if my hasByteOrderPrefix(Store's current) then
				return missing value
			end if
		else if theClass is integer then
			if Store's current < my smallestInteger or Store's current > my largestInteger then
				return missing value
			end if
		else if theClass is list then
			repeat with step from 1 to count Store's current
				set end of Store's pending to item step of Store's current
			end repeat
		else if theClass is record or theClass is in {«class SOMi», «class SOMc», «class SOMt», «class SOMd», «class SOMo»} then
			if theClass is record then
				set end of Store's nativeRecords to Store's current
			end if
			set Store's current to (Store's current) as record as list
			-- The bridge drops an explicit class:record field. Conservatively retain records holding that class value.
			if theClass is record and Store's current contains record then
				return missing value
			end if
			repeat with step from 1 to count Store's current
				set end of Store's pending to item step of Store's current
			end repeat
		else if theClass is class then
			if Store's current is not in {missing value, null, «class SOMi», «class SOMc», «class SOMt», «class SOMd», «class SOMo»} then
				return missing value
			end if
		else if theClass is not in {real, boolean, date} and Store's current is not missing value and Store's current is not null then
			return missing value
		end if
	end repeat
	-- Discover opaque values before reading labels, whose restoration bridges the record's values to Foundation.
	repeat with theIndex from 1 to count Store's nativeRecords
		set nestedPairs to my entries(item theIndex of Store's nativeRecords)
		repeat with thePair in nestedPairs
			set keyText to item 1 of thePair
			if my hasByteOrderPrefix(keyText) then
				return missing value
			end if
			set end of Store's keys to keyText
		end repeat
	end repeat
	return Store's keys
end keysForNativeRecord

-- `string id {}` crashes osascript, so the empty list is handled here.
on textFromCodes(theCodes)
	if theCodes = {} then
		return ""
	end if
	return string id theCodes
end textFromCodes

-- The code points with the ASCII capitals made lowercase, which is how AppleScript matches record labels.
on foldCase(theCodes)
	script Store
		property source : theCodes
		property folded : {}
	end script
	set theCount to count Store's source
	-- Most keys have no ASCII capitals, so leave their list intact until a change is needed.
	repeat with theIndex from 1 to theCount
		set theCode to item theIndex of Store's source
		if theCode ≥ 65 and theCode ≤ 90 then
			if theIndex > 1 then
				set Store's folded to items 1 thru (theIndex - 1) of Store's source
			end if
			repeat with remainderIndex from theIndex to theCount
				set theCode to item remainderIndex of Store's source
				if theCode ≥ 65 and theCode ≤ 90 then
					set end of Store's folded to theCode + 32
				else
					set end of Store's folded to theCode
				end if
			end repeat
			return Store's folded
		end if
	end repeat
	return theCodes
end foldCase

-- Compares code point lists by Unicode scalar value. Returns -1, 0, or 1.
on compareCodes(leftCodes, rightCodes)
	script comparison
		property leftSource : leftCodes
		property rightSource : rightCodes
	end script
	set leftCount to count comparison's leftSource
	set rightCount to count comparison's rightSource
	set shorter to leftCount
	if rightCount < shorter then
		set shorter to rightCount
	end if
	repeat with theIndex from 1 to shorter
		set leftCode to item theIndex of comparison's leftSource
		set rightCode to item theIndex of comparison's rightSource
		if leftCode < rightCode then
			return -1
		end if
		if leftCode > rightCode then
			return 1
		end if
	end repeat
	if leftCount < rightCount then
		return -1
	end if
	if leftCount > rightCount then
		return 1
	end if
	return 0
end compareCodes

on isBareKeyCode(theCode)
	return (theCode ≥ 97 and theCode ≤ 122) or (theCode ≥ 65 and theCode ≤ 90) or (theCode ≥ 48 and theCode ≤ 57) or theCode = 95 or theCode = 45
end isBareKeyCode

(*
Whether nonempty text is a bare key. Long keys use a native character-set scan; short keys use their existing code points.
*)
on isBareKeyText(theText, theCodes)
	script Store
		property codes : theCodes
	end script
	if Store's codes is missing value then
		set theCount to length of theText
	else
		set theCount to count Store's codes
	end if
	if theCount > 512 then
		set nativeText to my nativeString(theText)
		-- Character sets ignore lone surrogates; exact ASCII conversion rejects them as well as every non-ASCII key.
		if not (nativeText's canBeConvertedToEncoding:(current application's NSASCIIStringEncoding)) as boolean then
			return false
		end if
		if my nonBareKeyCharacters is missing value then
			set my nonBareKeyCharacters to (current application's NSCharacterSet's characterSetWithCharactersInString:"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")'s invertedSet()
		end if
		return ((nativeText's rangeOfCharacterFromSet:(my nonBareKeyCharacters))'s location) as real > 1.0E+18
	end if
	if Store's codes is missing value then
		set Store's codes to my codePoints(theText)
	end if
	set theCount to count Store's codes
	if theCount = 0 then
		return false
	end if
	repeat with step from 1 to theCount
		-- Inlined in this hot loop so a short key needs no handler call per character.
		set theCode to item step of Store's codes
		if not ((theCode ≥ 97 and theCode ≤ 122) or (theCode ≥ 65 and theCode ≤ 90) or (theCode ≥ 48 and theCode ≤ 57) or theCode = 95 or theCode = 45) then
			return false
		end if
	end repeat
	return true
end isBareKeyText

(*
Formats a long string with native scans and replacements without building an AppleScript list of code points. Returns missing value for short strings or invalid text, which the general formatter handles.
*)
on longFormattedString(theText)
	-- Blanket native string formatting was 2% to 18% slower, so retain the short-string path.
	if length of theText ≤ 512 then
		return missing value
	end if
	if my nonLiteralStringCharacters is missing value then
		set my nonLiteralStringCharacters to current application's NSMutableCharacterSet's characterSetWithRange:{location:0, |length|:32}
		my nonLiteralStringCharacters's addCharactersInString:"'"
		my nonLiteralStringCharacters's addCharactersInRange:{location:127, |length|:1}
	end if
	set theString to my nativeString(theText)
	set needsEscapes to ((theString's rangeOfCharacterFromSet:(my nonLiteralStringCharacters))'s location) as real < 1.0E+18
	if (theString's dataUsingEncoding:(current application's NSUTF8StringEncoding) allowLossyConversion:false) is missing value then
		return missing value
	end if
	if not needsEscapes then
		return "'" & theText & "'"
	end if
	if ((theString's rangeOfString:return options:(current application's NSLiteralSearch))'s location) as real < 1.0E+18 then
		return missing value
	end if
	set escapedText to current application's NSMutableString's stringWithString:theString
	repeat with replacementPair in {{"\\", "\\\\"}, {quote, "\\\""}, {linefeed, "\\n"}, {tab, "\\t"}}
		escapedText's replaceOccurrencesOfString:(item 1 of replacementPair) withString:(item 2 of replacementPair) options:(current application's NSLiteralSearch) range:{location:0, |length|:escapedText's |length|()}
	end repeat
	if my stringControlExpression is missing value then
		set my stringControlExpression to current application's NSRegularExpression's regularExpressionWithPattern:"[\\x00-\\x08\\x0B\\x0C\\x0E-\\x1F\\x7F]" options:0 |error|:(missing value)
	end if
	set controlMatches to my stringControlExpression's matchesInString:escapedText options:0 range:{location:0, |length|:escapedText's |length|()}
	repeat with matchIndex from ((controlMatches's |count|()) as integer) - 1 to 0 by -1
		set matchedRange to (controlMatches's objectAtIndex:matchIndex)'s range()
		set theCode to (escapedText's characterAtIndex:(location of matchedRange)) as integer
		escapedText's replaceCharactersInRange:matchedRange withString:("\\u{" & my lowercaseHex(theCode) & "}")
	end repeat
	return quote & my textOfString(escapedText) & quote
end longFormattedString

on isDigitCode(theCode)
	return theCode ≥ 48 and theCode ≤ 57
end isDigitCode

-- Whether the codes at the indexes are all digits.
on isDigitRun(theCodes, theIndexes)
	script Store
		property codes : theCodes
	end script
	repeat with theIndex in theIndexes
		set theCode to item theIndex of Store's codes
		if theCode < 48 or theCode > 57 then
			return false
		end if
	end repeat
	return true
end isDigitRun

(*
Whether a scalar is a horizontal SOML space. Other Unicode whitespace is never accepted implicitly.
*)
on isHorizontalSpaceCode(theCode)
	return theCode is in {32, 9}
end isHorizontalSpaceCode

(*
Whether a scalar can end a SOML value. A slash ends the token; comment validation follows in trivia parsing.
*)
on isValueEndCode(theCode)
	return theCode is in {32, 9, 10, 44, 93, 125, 35, 47, -1}
end isValueEndCode

(*
Whether a scalar is an ASCII letter, without locale or Unicode case folding.
*)
on isLetterCode(theCode)
	return (theCode ≥ 97 and theCode ≤ 122) or (theCode ≥ 65 and theCode ≤ 90)
end isLetterCode

(*
Whether a scalar continues a numeric token, including instant separators and duration units.
*)
on isNumberTokenCode(theCode)
	return my isBareKeyCode(theCode) or theCode is in {46, 58, 43}
end isNumberTokenCode

on hexText(theNumber, minimumLength)
	return my hexadecimalText(theNumber, minimumLength, "0123456789ABCDEF")
end hexText

(*
Formats a nonnegative integer in hexadecimal using the supplied digits and minimum width.
*)
on hexadecimalText(theNumber, minimumLength, digits)
	set theText to ""
	repeat
		set theText to character (theNumber mod 16 + 1) of digits & theText
		set theNumber to theNumber div 16
		if theNumber = 0 then
			exit repeat
		end if
	end repeat
	return padLeft(theText, minimumLength)
end hexadecimalText

on formatCodePoint(theCode)
	return "U+" & hexText(theCode, 4)
end formatCodePoint

-- A character as an error message shows it, such as “$” or U+00A0 (NO-BREAK SPACE).
on describeCode(theCode)
	if theCode = -1 then
		return "the end of the document"
	end if
	if theCode = 10 then
		return "a line break"
	end if
	repeat with entry in my characterNames
		if item 1 of entry = theCode then
			set theName to item 2 of entry
			if theCode is in my namedWhitespace then
				set theName to theName & "; only space, tab, and line feed are whitespace"
			end if
			return formatCodePoint(theCode) & " (" & theName & ")"
		end if
	end repeat
	if isInvisibleCode(theCode) then
		return formatCodePoint(theCode)
	end if
	return "“" & textFromCodes({theCode}) & "”"
end describeCode

(*
Whether a character is invisible or ambiguous, so that an error shows its code point: a control, format, private-use, surrogate, separator, or default-ignorable character. Without Unicode tables, unassigned code points are shown as characters.
*)
on isInvisibleCode(theCode)
	if theCode < 32 or (theCode ≥ 127 and theCode ≤ 160) or theCode = 173 or theCode = 847 or theCode = 1564 or theCode = 4447 or theCode = 4448 or theCode = 5760 or theCode = 6068 or theCode = 6069 or (theCode ≥ 6155 and theCode ≤ 6159) then
		return true
	end if
	if (theCode ≥ 8192 and theCode ≤ 8207) or (theCode ≥ 8232 and theCode ≤ 8239) or (theCode ≥ 8287 and theCode ≤ 8303) or theCode = 12288 or theCode = 12644 then
		return true
	end if
	if (theCode ≥ 55296 and theCode ≤ 63743) or (theCode ≥ 65024 and theCode ≤ 65039) or theCode = 65279 or theCode = 65440 or (theCode ≥ 65520 and theCode ≤ 65531) or theCode = 65534 or theCode = 65535 then
		return true
	end if
	return (theCode ≥ 917504 and theCode ≤ 921599) or theCode ≥ 983040
end isInvisibleCode

(*
Text as an error message shows it, escaping terminal control characters other than tab and Unicode direction controls, so that a key from a document cannot send commands to a terminal or change the direction of its diagnostic.
*)
on sanitize(theText)
	if length of theText > 512 then
		set nativeText to my nativeString(theText)
		if my terminalCharacters is missing value then
			set my terminalCharacters to current application's NSMutableCharacterSet's characterSetWithRange:{location:0, |length|:9}
			repeat with theRange in {{10, 22}, {127, 33}, {8203, 5}, {8232, 7}, {8288, 16}}
				my terminalCharacters's addCharactersInRange:{location:item 1 of theRange, |length|:item 2 of theRange}
			end repeat
			my terminalCharacters's addCharactersInString:(my textFromCodes({173, 1564, 65279}))
		end if
		-- Native sets skip lone surrogates, so safe text must also be convertible without loss.
		if ((nativeText's rangeOfCharacterFromSet:(my terminalCharacters))'s location) as real > 1.0E+18 and (nativeText's dataUsingEncoding:(current application's NSUTF8StringEncoding) allowLossyConversion:false) is not missing value then
			return theText
		end if
	end if
	script Store
		property codes : codePoints(theText)
		property pieces : {}
	end script
	set theCount to count Store's codes
	set chunkStart to 1
	repeat with step from 1 to theCount
		set theCode to item step of Store's codes
		if isTerminalCode(theCode) then
			if step > chunkStart then
				set end of Store's pieces to textFromCodes(items chunkStart thru (step - 1) of Store's codes)
			end if
			set end of Store's pieces to "\\u{" & my lowercaseHex(theCode) & "}"
			set chunkStart to step + 1
		end if
	end repeat
	if chunkStart = 1 then
		return theText
	end if
	if chunkStart ≤ theCount then
		set end of Store's pieces to textFromCodes(items chunkStart thru theCount of Store's codes)
	end if
	return joinTexts(Store's pieces, "")
end sanitize

on isTerminalCode(theCode)
	return (theCode < 32 and theCode is not 9) or (theCode ≥ 127 and theCode < 160) or theCode is in {173, 1564, 65279} or (theCode ≥ 8203 and theCode ≤ 8207) or (theCode ≥ 8232 and theCode ≤ 8238) or (theCode ≥ 8288 and theCode ≤ 8303) or (theCode ≥ 55296 and theCode ≤ 57343)
end isTerminalCode

on lowercaseHex(theNumber)
	return my hexadecimalText(theNumber, 0, "0123456789abcdef")
end lowercaseHex

on abbreviate(theText, maximumLength)
	-- The reference bounds previews by UTF-16 units, without splitting a surrogate pair. Native slicing also bounds one arbitrarily long combining cluster.
	set theString to my nativeString(theText)
	if (theString's |length|()) as integer ≤ maximumLength then
		return theText
	end if
	set prefixLength to maximumLength
	set lastCode to (theString's characterAtIndex:(prefixLength - 1)) as integer
	if lastCode ≥ 55296 and lastCode ≤ 56319 then
		set prefixLength to prefixLength - 1
	end if
	return my textOfString(theString's substringToIndex:prefixLength) & "…"
end abbreviate

(*
A bounded diagnostic preview of Unicode scalar values. At most one extra scalar beyond the UTF-16 limit is needed, so large invalid tokens need no complete text conversion.
*)
on abbreviateCodes(theCodes, maximumLength)
	script Store
		property codes : theCodes
	end script
	if (count Store's codes) > maximumLength + 1 then
		set Store's codes to items 1 thru (maximumLength + 1) of Store's codes
	end if
	return my abbreviate(my textFromCodes(Store's codes), maximumLength)
end abbreviateCodes

on describeKey(theKey)
	if my isBareKeyText(theKey, missing value) then
		return abbreviate(theKey, 40)
	end if
	return jsonQuote(abbreviate(theKey, 40))
end describeKey

-- Text in double quotes with JSON's escapes, as the reference implementation shows a key that is not bare.
on jsonQuote(theText)
	return my quoteEscapedText(theText, codePoints(theText), true)
end jsonQuote

(*
Text in double quotes with JSON diagnostic escapes or SOML value escapes.
*)
on quoteEscapedText(theText, theCodes, usesJSONEscapes)
	script Store
		property codes : theCodes
		property parts : {}
	end script
	set theCount to count Store's codes
	set chunkStart to 1
	repeat with step from 1 to theCount
		set theCode to item step of Store's codes
		if theCode < 32 or theCode is in {34, 92} or (not usesJSONEscapes and theCode = 127) then
			if step > chunkStart then
				set end of Store's parts to textFromCodes(items chunkStart thru (step - 1) of Store's codes)
			end if
			if theCode = 34 then
				set end of Store's parts to "\\\""
			else if theCode = 92 then
				set end of Store's parts to "\\\\"
			else if theCode = 10 then
				set end of Store's parts to "\\n"
			else if theCode = 9 then
				set end of Store's parts to "\\t"
			else if usesJSONEscapes and theCode = 8 then
				set end of Store's parts to "\\b"
			else if usesJSONEscapes and theCode = 12 then
				set end of Store's parts to "\\f"
			else if usesJSONEscapes and theCode = 13 then
				set end of Store's parts to "\\r"
			else if usesJSONEscapes then
				set end of Store's parts to "\\u" & lowercaseHexPadded(theCode, 4)
			else
				set end of Store's parts to "\\u{" & lowercaseHex(theCode) & "}"
			end if
			set chunkStart to step + 1
		end if
	end repeat
	if chunkStart = 1 then
		return "\"" & theText & "\""
	end if
	if chunkStart ≤ theCount then
		set end of Store's parts to textFromCodes(items chunkStart thru theCount of Store's codes)
	end if
	return "\"" & joinTexts(Store's parts, "") & "\""
end quoteEscapedText

on lowercaseHexPadded(theNumber, theLength)
	return my hexadecimalText(theNumber, theLength, "0123456789abcdef")
end lowercaseHexPadded

on describeClass(theValue)
	set theClass to class of theValue
	if theClass is record then
		return "a record"
	else if theClass is in {«class SOMi», «class SOMc», «class SOMt», «class SOMd», «class SOMo»} then
		return "a " & my className(theClass)
	else if theClass is list then
		return "a list"
	else if theClass is text then
		if not my isTextValue(theValue) then
			return "raw data"
		end if
		return "text"
	else if theClass is integer then
		return "an integer"
	else if theClass is real then
		return "a real"
	else if theClass is boolean then
		return "a boolean"
	else if theClass is date then
		return "a date"
	else if theValue is missing value then
		return "missing value"
	else if theClass is script then
		return "a script object"
	else if theClass is application then
		return "an application"
	end if
	-- An Objective-C object answers `class` with its own class.
	try
		if (theValue's respondsToSelector:"description") as boolean then
			return "an Objective-C object, which needs converting to an AppleScript value first, as with `as text` or `as list`"
		end if
	end try
	try
		return "a value of class " & (theClass as text)
	on error
		return "an unsupported value"
	end try
end describeClass

(*
Whether a value is a scalar of the expected class. A physical record can claim a scalar class, but coercing it to a list exposes its fields instead of one scalar item.
*)
on hasScalarShape(theValue, expectedClass)
	if class of theValue is not expectedClass then
		return false
	end if
	set scalarItems to theValue as list
	return (count scalarItems) is 1 and class of item 1 of scalarItems is expectedClass
end hasScalarShape

(*
Whether a value is actual AppleScript text. A physical record can claim the class text, and raw `utxt` data reports it without providing a length.
*)
on isTextValue(theValue)
	if not my hasScalarShape(theValue, text) then
		return false
	end if
	try
		get length of theValue
		return true
	end try
	return false
end isTextValue

(*
Whether a value is an actual AppleScript list. A physical record may claim the class list, but its first item cannot be indexed.
*)
on isListValue(theValue)
	if class of theValue is not list then
		return false
	end if
	try
		if (count theValue) > 0 then
			get item 1 of theValue
		end if
		return true
	on error number errorNumber
		if errorNumber is -128 then
			error number -128
		end if
	end try
	return false
end isListValue

(*
Whether a value is actual text made of Unicode scalar values. The prefix keeps leading U+FEFF or U+FFFE intact through the text bridge.
*)
on isUnicodeTextValue(theValue)
	if not my isTextValue(theValue) then
		return false
	end if
	set nativeText to my nativeString(theValue)
	return (nativeText's dataUsingEncoding:(current application's NSUTF8StringEncoding) allowLossyConversion:false) is not missing value
end isUnicodeTextValue

on posixPath(theFile)
	if class of theFile is text then
		if my isTextValue(theFile) then
			return theFile
		end if
	else if class of theFile is in {alias, «class furl»} then
		try
			return POSIX path of theFile
		end try
	end if
	error "decodeFile() expects a POSIX path, a file, or an alias, but got " & my describeClass(theFile) & "." number wrongTypeErrorNumber
end posixPath

(*
Reports the first invalid UTF-8 sequence at its position. The bytes are read through Latin-1, which maps every byte to the code point of the same value, and checked as the reference implementation does: the bounds of a lead byte and its continuation bytes rule out overlong forms, surrogates, and values above U+10FFFF.
*)
on failInvalidUTF8(theData)
	set byteCount to (theData's |length|()) as integer
	script Store
		property bytes : {}
	end script
	set windowStart to 0
	set windowEnd to 0
	set lineNumber to 1
	set columnNumber to 1
	set theIndex to 1
	set invalidIndex to 0
	repeat while theIndex ≤ byteCount
		-- Keep at most one small window, with enough bytes to check a complete UTF-8 sequence.
		if theIndex + 3 > windowEnd and windowEnd < byteCount then
			set windowStart to theIndex - 1
			set windowEnd to windowStart + 4096
			if windowEnd > byteCount then
				set windowEnd to byteCount
			end if
			set Store's bytes to my bytesOf(theData, windowStart, windowEnd - windowStart)
		end if
		set localIndex to theIndex - windowStart
		set theByte to item localIndex of Store's bytes
		if theByte < 128 then
			if theByte = 10 then
				set lineNumber to lineNumber + 1
				set columnNumber to 1
			else
				set columnNumber to columnNumber + 1
			end if
			set theIndex to theIndex + 1
		else
			-- The bounds of a lead byte and its continuation bytes, read through the property, which is fast.
			set sequenceLength to 0
			if theByte ≥ 194 and theByte ≤ 244 then
				if theByte ≥ 240 then
					set sequenceLength to 4
				else if theByte ≥ 224 then
					set sequenceLength to 3
				else
					set sequenceLength to 2
				end if
				if theIndex + sequenceLength - 1 > byteCount then
					set sequenceLength to 0
				else
					set secondByte to item (localIndex + 1) of Store's bytes
					if secondByte < 128 or secondByte > 191 or (theByte = 224 and secondByte < 160) or (theByte = 237 and secondByte > 159) or (theByte = 240 and secondByte < 144) or (theByte = 244 and secondByte > 143) then
						set sequenceLength to 0
					else
						repeat with continuation from localIndex + 2 to localIndex + sequenceLength - 1
							set continuationByte to item continuation of Store's bytes
							if continuationByte < 128 or continuationByte > 191 then
								set sequenceLength to 0
								exit repeat
							end if
						end repeat
					end if
				end if
			end if
			if sequenceLength = 0 then
				set invalidIndex to theIndex
				exit repeat
			end if
			set columnNumber to columnNumber + 1
			set theIndex to theIndex + sequenceLength
		end if
	end repeat
	if invalidIndex = 0 then
		error "The file is not valid UTF-8" number my invalidDocumentErrorNumber from {reason:"The file is not valid UTF-8", |line|:1, |column|:1}
	end if
	set remainingLength to byteCount - invalidIndex + 1
	if remainingLength > 4 then
		set remainingLength to 4
	end if
	set restBytes to my bytesOf(theData, invalidIndex - 1, remainingLength)
	if my isTruncatedUTF8(restBytes) then
		set reason to "Incomplete UTF-8 sequence at the end of the input"
	else
		set reason to "Invalid UTF-8 byte 0x" & hexText(item 1 of restBytes, 2)
	end if
	error reason & " at line " & lineNumber & ", column " & columnNumber number my invalidDocumentErrorNumber from {reason:reason, |line|:lineNumber, |column|:columnNumber}
end failInvalidUTF8

-- Byte values, through Latin-1, which maps every byte to the code point of the same value.
on bytesOf(theData, theLocation, theLength)
	if theLength = 0 then
		return {}
	end if
	if theLocation is not 0 or theLength is not (theData's |length|()) as integer then
		set theData to theData's subdataWithRange:{location:theLocation, |length|:theLength}
	end if
	set theString to current application's NSString's alloc()'s initWithData:theData encoding:(current application's NSISOLatin1StringEncoding)
	return codePoints(theString as text)
end bytesOf

-- Whether the bytes are the start of a valid sequence that the end of the input cuts short.
on isTruncatedUTF8(theBytes)
	set lead to item 1 of theBytes
	if lead < 194 or lead > 244 then
		return false
	end if
	if lead ≥ 240 then
		set needed to 4
	else if lead ≥ 224 then
		set needed to 3
	else
		set needed to 2
	end if
	if (count theBytes) ≥ needed then
		return false
	end if
	repeat with theIndex from 2 to count theBytes
		set theByte to item theIndex of theBytes
		if theByte < 128 or theByte > 191 then
			return false
		end if
		if theIndex = 2 then
			if (lead = 224 and theByte < 160) or (lead = 237 and theByte > 159) or (lead = 240 and theByte < 144) or (lead = 244 and theByte > 143) then
				return false
			end if
		end if
	end repeat
	return true
end isTruncatedUTF8

(*
An `NSString` as text. The conversion drops a U+FEFF at the start and byte-swaps the text after a U+FFFE there, so such characters at the start are added by hand.
*)
on textOfString(theString)
	script Store
		property prefixCodes : {}
	end script
	set theLength to (theString's |length|()) as integer
	set prefixLength to 0
	repeat while prefixLength < theLength
		set theCode to (theString's characterAtIndex:prefixLength) as integer
		if theCode is not 65279 and theCode is not 65534 then
			exit repeat
		end if
		set end of Store's prefixCodes to theCode
		set prefixLength to prefixLength + 1
	end repeat
	if prefixLength = 0 then
		return theString as text
	end if
	return textFromCodes(Store's prefixCodes) & ((theString's substringFromIndex:prefixLength) as text)
end textOfString

-- A tagged value whose text is not valid is an argument of the wrong kind.
on failTagged(handlerName, reason, errorNumber)
	if errorNumber is not my invalidDocumentErrorNumber then
		error reason number errorNumber
	end if
	error my sanitize(handlerName & " got an invalid value: " & reason) number my wrongTypeErrorNumber
end failTagged

on taggedText(theValue, theClass, handlerName)
	try
		if class of theValue is theClass then
			set theText to value of theValue
			if my isUnicodeTextValue(theText) then
				return theText
			end if
		end if
	end try
	set expectedName to my className(theClass)
	error handlerName & " expects a " & expectedName & ", {class:" & expectedName & ", value:…}, but got " & my describeClass(theValue) & "." number my wrongTypeErrorNumber
end taggedText

-- The terminology of a tagged value's class.
on className(theClass)
	if theClass is «class SOMi» then
		return "SOML int"
	else if theClass is «class SOMc» then
		return "SOML date"
	else if theClass is «class SOMt» then
		return "SOML instant"
	else if theClass is «class SOMd» then
		return "SOML duration"
	else if theClass is «class SOMo» then
		return "SOML object"
	end if
	if class of theClass is text then
		return theClass
	end if
	if class of theClass is not class then
		return "something that is not a class"
	end if
	try
		return theClass as text
	on error
		return "an unknown class"
	end try
end className

(*
Makes records with any labels. A record made from {«class usrf»:{key, value, …}} holds the labels only after it goes through an Apple event, which `run script` does, for every record inside the value at once.
*)
on materializeRecords(theValue)
	return run script "on run {theValue}
	return theValue
end run" with parameters {theValue}
end materializeRecords

(*
The keys whose spelling AppleScript does not keep, or whose native labels cannot be read, in a probe: a record from `materializeRecords` with the keys as labels. A label keeps the first spelling that the process saw, ignoring ASCII letter case. The probe is read as a dictionary, which has the spelling of each label, because a display lowers the ASCII capitals of a label in bars. Sets of strings compare them exactly.
*)
on respelledKeys(probeRecord, keyTexts)
	try
		-- Some long labels corrupt AppleScript's display even when a dictionary keeps their spelling.
		my entries(probeRecord)
	on error number errorNumber
		if errorNumber is -128 then
			error number -128
		end if
		return keyTexts
	end try
	set keptKeys to (current application's NSDictionary's dictionaryWithDictionary:probeRecord)'s allKeys()
	set respelled to current application's NSMutableSet's setWithArray:keyTexts
	respelled's minusSet:(current application's NSSet's setWithArray:keptKeys)
	return (respelled's allObjects()) as list
end respelledKeys

(*
The shared context for the library's pure numeric conversion functions. Reusing it avoids creating a virtual machine for each document.
*)
on floatJavaScriptContext()
	if my cachedJavaScriptContext is missing value then
		set my cachedJavaScriptContext to current application's JSContext's new()
	end if
	return my cachedJavaScriptContext
end floatJavaScriptContext

-- Calls a JavaScript function with one argument, a list, and returns its result, an array, as a list.
on callJavaScript(theContext, functionName, theFunction, theArgument)
	set theFunctionValue to theContext's objectForKeyedSubscript:functionName
	if (theFunctionValue's isUndefined()) as boolean then
		set theFunctionValue to theContext's evaluateScript:theFunction
		theContext's setObject:theFunctionValue forKeyedSubscript:functionName
	end if
	set theResult to theFunctionValue's callWithArguments:{theArgument}
	return (theResult's toArray()) as list
end callJavaScript

-- The calendar: days since 1970-01-01 in the proleptic Gregorian calendar, after Howard Hinnant's algorithms.
on daysFromCivil(theYear, theMonth, theDay)
	if theMonth ≤ 2 then
		set theYear to theYear - 1
	end if
	set era to theYear div 400
	set yearOfEra to theYear - era * 400
	if theMonth > 2 then
		set shiftedMonth to theMonth - 3
	else
		set shiftedMonth to theMonth + 9
	end if
	set dayOfYear to (153 * shiftedMonth + 2) div 5 + theDay - 1
	set dayOfEra to yearOfEra * 365 + yearOfEra div 4 - yearOfEra div 100 + dayOfYear
	return era * 146097 + dayOfEra - 719468
end daysFromCivil

on civilFromDays(theDays)
	set shifted to theDays + 719468
	set era to shifted div 146097
	set dayOfEra to shifted - era * 146097
	set yearOfEra to (dayOfEra - dayOfEra div 1460 + dayOfEra div 36524 - dayOfEra div 146096) div 365
	set theYear to yearOfEra + era * 400
	set dayOfYear to dayOfEra - (365 * yearOfEra + yearOfEra div 4 - yearOfEra div 100)
	set shiftedMonth to (5 * dayOfYear + 2) div 153
	set theDay to dayOfYear - (153 * shiftedMonth + 2) div 5 + 1
	if shiftedMonth < 10 then
		set theMonth to shiftedMonth + 3
	else
		set theMonth to shiftedMonth - 9
	end if
	if theMonth ≤ 2 then
		set theYear to theYear + 1
	end if
	return {theYear, theMonth, theDay}
end civilFromDays

(*
A date alone is a calendar value, not an instant. The first invalid proleptic Gregorian component, shared with the calendar part of instants, or missing value when valid.
*)
on calendarDateProblem(theYear, theMonth, theDay)
	if theYear < 1 or theYear > 9999 then
		return "the year must be 0001 to 9999"
	end if
	if theMonth < 1 or theMonth > 12 then
		return "the month must be 01 to 12"
	end if
	set lastDay to daysInMonth(theYear, theMonth)
	if theDay < 1 or theDay > lastDay then
		return "the day must be 01 to " & lastDay & " in that month"
	end if
	return missing value
end calendarDateProblem

on daysInMonth(theYear, theMonth)
	if theMonth = 2 then
		if theYear mod 4 = 0 and (theYear mod 100 is not 0 or theYear mod 400 = 0) then
			return 29
		end if
		return 28
	end if
	if theMonth is in {4, 6, 9, 11} then
		return 30
	end if
	return 31
end daysInMonth

on padNumber(theNumber, theLength)
	return padLeft(wholeNumberText(theNumber), theLength)
end padNumber

-- Text with “0” added at the start up to a minimum length.
on padLeft(theText, minimumLength)
	repeat while length of theText < minimumLength
		set theText to "0" & theText
	end repeat
	return theText
end padLeft

-- A nonnegative whole real below 2^53 as decimal digits, without the locale that `as text` uses.
on wholeNumberText(theNumber)
	if theNumber ≤ largestInteger then
		return (theNumber as integer) as text
	end if
	set high to theNumber div 1000000
	set low to theNumber - high * 1000000
	return wholeNumberText(high) & padNumber(low, 6)
end wholeNumberText

(*
The canonical form of an instant, from whole seconds since 1970 in UTC and a fraction of up to nine digits.
*)
on formatInstant(epochSeconds, fractionCodes)
	set theDays to epochSeconds div 86400
	set secondOfDay to epochSeconds - theDays * 86400
	if secondOfDay < 0 then
		set theDays to theDays - 1
		set secondOfDay to secondOfDay + 86400
	end if
	set {theYear, theMonth, theDay} to civilFromDays(theDays as integer)
	set secondOfDay to secondOfDay as integer
	set theText to padNumber(theYear, 4) & "-" & padNumber(theMonth, 2) & "-" & padNumber(theDay, 2) & "T" & padNumber(secondOfDay div 3600, 2) & ":" & padNumber(secondOfDay mod 3600 div 60, 2) & ":" & padNumber(secondOfDay mod 60, 2)
	set fractionCodes to trimTrailingZeros(fractionCodes)
	if fractionCodes is not {} then
		set theText to theText & "." & textFromCodes(fractionCodes)
	end if
	return theText & "Z"
end formatInstant

(*
The text of an instant that is already in canonical form, in UTC with a fraction that has no zero at its end, as in 2026-10-10T16:25:41.111Z, which is how most instants are written. Returns missing value for anything else, which the general path reads.
*)
on canonicalUTCInstant(theCodes)
	set theCount to count theCodes
	if theCount < 20 or theCount = 21 or theCount > 30 then
		return missing value
	end if
	-- The codes are taken apart once, because each item of a list takes longer to get than a variable.
	set {c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11, c12, c13, c14, c15, c16, c17, c18, c19, c20} to items 1 thru 20 of theCodes
	if c5 is not 45 or c8 is not 45 or c11 is not 84 or c14 is not 58 or c17 is not 58 or item theCount of theCodes is not 90 then
		return missing value
	end if
	-- Every other code up to the seconds is a digit, and the minute and the second start with at most a 5.
	if c1 < 48 or c1 > 57 or c2 < 48 or c2 > 57 or c3 < 48 or c3 > 57 or c4 < 48 or c4 > 57 or c6 < 48 or c6 > 57 or c7 < 48 or c7 > 57 or c9 < 48 or c9 > 57 or c10 < 48 or c10 > 57 or c12 < 48 or c12 > 57 or c13 < 48 or c13 > 57 or c15 < 48 or c15 > 53 or c16 < 48 or c16 > 57 or c18 < 48 or c18 > 53 or c19 < 48 or c19 > 57 then
		return missing value
	end if
	if theCount > 20 then
		if c20 is not 46 or item (theCount - 1) of theCodes = 48 then
			return missing value
		end if
		repeat with theIndex from 21 to theCount - 1
			set theCode to item theIndex of theCodes
			if theCode < 48 or theCode > 57 then
				return missing value
			end if
		end repeat
	end if
	set theYear to (c1 - 48) * 1000 + (c2 - 48) * 100 + (c3 - 48) * 10 + c4 - 48
	set theMonth to (c6 - 48) * 10 + c7 - 48
	set theDay to (c9 - 48) * 10 + c10 - 48
	if theYear = 0 or theMonth < 1 or theMonth > 12 or theDay < 1 or theDay > daysInMonth(theYear, theMonth) or (c12 - 48) * 10 + c13 - 48 > 23 then
		return missing value
	end if
	return string id theCodes
end canonicalUTCInstant

on trimTrailingZeros(theCodes)
	set theCount to count theCodes
	set theEnd to theCount
	repeat while theEnd > 0 and item theEnd of theCodes = 48
		set theEnd to theEnd - 1
	end repeat
	if theEnd = 0 then
		return {}
	end if
	if theEnd = theCount then
		return theCodes
	end if
	return items 1 thru theEnd of theCodes
end trimTrailingZeros

(*
The canonical form of a duration, from its magnitude as whole seconds and nanoseconds.
*)
on formatDuration(theSeconds, theNanoseconds, isNegative)
	set theText to ""
	if isNegative then
		set theText to "-"
	end if
	set theHours to theSeconds div 3600
	set theMinutes to theSeconds mod 3600 div 60
	set wholeSeconds to theSeconds mod 60
	if theHours > 0 then
		set theText to theText & wholeNumberText(theHours) & "h"
	end if
	if theMinutes > 0 then
		set theText to theText & ((theMinutes as integer) as text) & "m"
	end if
	if wholeSeconds > 0 or theNanoseconds > 0 or (theHours = 0 and theMinutes = 0) then
		set theText to theText & ((wholeSeconds as integer) as text)
		if theNanoseconds > 0 then
			set theText to theText & "." & textFromCodes(trimTrailingZeros(id of padNumber(theNanoseconds, 9)))
		end if
		set theText to theText & "s"
	end if
	return theText
end formatDuration

-- Reader

(*
A reader of one document. It splits the text into lines, which it converts to code points one at a time, and reads with a cursor in a line.
*)
on makeReader(theText)
	set thePieces to my splitText(theText, linefeed)
	script Reader
		property pieces : thePieces
		property pieceCount : count thePieces
		property lineIndex : 0
		property sourceCodes : {}
		property cursor : 1
		property sourceText : theText
		property scanCodes : {}
		-- Every document is checked for encoding errors before parsing.
		-- File byte order marks are rejected before creating the reader.
		property isChecked : false
		-- Whether a piece holds a line feed of its own, so that piece indexes are not line numbers.
		property hasInnerLineBreak : false

		-- The collection being read, and the ones around it.
		property frameKind : 0 -- 1: object without braces, 2: object, 3: array
		property frameItems : {}
		property frameBlocks : {}
		property frameLine : 0
		property framePosition : 0
		property frameFolded : {}
		property frameExact : {}
		property frameKeySets : missing value
		property frameCollides : false
		property frameKey : missing value
		property frameKeyCodes : {}
		property frameKeyFolded : {}
		property frameKeyLine : 0
		property frameKeyPosition : 0
		property stack : {}
		property stackDepth : 0
		property depth : 0
		property madeRecord : false
		-- Whether an entry of the object without braces has been read.
		property hasEntry : false

		-- Floats waiting for conversion: {list, index, text, line, position, token text}.
		property pendingFloats : {}
		property cachedInfinities : missing value
		-- The content lines of the block string being read, and the code points of one of them.
		property blockLines : {}
		property lineSource : {}

		(*
		What keeps an object from being a record. A record gets its labels, and its texts, through an Apple event (see `materializeRecords`), which keeps one spelling of a label in a process, ignoring ASCII letter case, and which drops or byte-swaps a U+FEFF or U+FFFE at the start of a text. So objects with a key whose spelling AppleScript does not keep, `badKeys`, are tagged objects, and so is every object, `isAllObjects`, when a text starts with one of those characters, when the document has more than `maximumDistinctKeys` keys, and when AppleScript has no room for the labels.
		*)
		property isAllObjects : false
		property badKeys : {}
		property frameHasBadKey : false
		-- The distinct keys of the document, in the order they first appear, found through an exact native string set.
		property distinctKeys : {}
		property distinctCodes : {}
		property keySet : missing value

		on raise(reason, atLine, atPosition)
			error reason number invalidDocumentErrorNumber from {reason, atLine, atPosition}
		end raise

		on fail(reason)
			raise(reason, my lineIndex, my cursor)
		end fail

		on loadLine(theIndex)
			set my lineIndex to theIndex
			set theText to item theIndex of my pieces
			-- `codePoints`, inlined for a line of ordinary length.
			if length of theText > 512 then
				set theCodes to codePoints(theText)
			else
				set theCodes to (id of theText) as list
			end if
			if theIndex < my pieceCount then
				set end of theCodes to 10
			else
				set end of theCodes to -1
			end if
			set my sourceCodes to theCodes
			set my cursor to 1
		end loadLine

		-- Moves past the line feed at `cursor`.
		on crossLineBreak()
			if my cursor < (count my sourceCodes) then
				set my cursor to (my cursor) + 1
			else
				loadLine((my lineIndex) + 1)
			end if
		end crossLineBreak

		on locate(atLine, atPosition)
			if not my hasInnerLineBreak then
				return {atLine, atPosition}
			end if
			set lineNumber to 1
			set columnNumber to 1
			repeat with theIndex from 1 to atLine
				set my scanCodes to codePoints(item theIndex of my pieces)
				set codeCount to count my scanCodes
				set limit to codeCount
				if theIndex = atLine then
					set limit to atPosition - 1
				end if
				repeat with step from 1 to limit
					if step ≤ codeCount and item step of my scanCodes = 10 then
						set lineNumber to lineNumber + 1
						set columnNumber to 1
					else
						set columnNumber to columnNumber + 1
					end if
				end repeat
				if theIndex < atLine then
					set lineNumber to lineNumber + 1
					set columnNumber to 1
				end if
			end repeat
			return {lineNumber, columnNumber}
		end locate

		(*
		The error to report. Errors that apply to every character come first, then the first float that is out of range, which was read before the error, and then the error itself.
		*)
		on prioritize(details)
			try
				convertFloats()
			on error message number errorNumber from floatDetails
				if errorNumber is not invalidDocumentErrorNumber or class of floatDetails is not list then
					error message number errorNumber from floatDetails
				end if
				return floatDetails
			end try
			return details
		end prioritize

		(*
		Characters that are errors wherever they are: a byte order mark at the start, control characters other than tab and line feed, and lone surrogates. They are looked for once, by Foundation, which is fast, so that the reader needs no check of its own. Foundation gets the text through a conversion that drops a U+FEFF at the start and byte-swaps the text after a U+FFFE there, so a text that starts with one is checked by the slower exact scan instead. Also finds out whether every piece is one line.
		*)
		on checkCharacters()
			set my isChecked to true
			set theString to current application's NSString's stringWithString:(my sourceText)
			set isClean to not hasByteOrderPrefix(item 1 of my pieces)
			-- Whether every piece is one line, which the position of an error needs too. A literal search counts every line feed, also one that a combining mark follows.
			if my documentLineBreakExpression is missing value then
				set my documentLineBreakExpression to current application's NSRegularExpression's regularExpressionWithPattern:(linefeed) options:0 |error|:(missing value)
			end if
			set lineBreakCount to (my documentLineBreakExpression's numberOfMatchesInString:theString options:0 range:{location:0, |length|:theString's |length|()}) as integer
			set my hasInnerLineBreak to not isClean or lineBreakCount is not (my pieceCount) - 1
			if isClean then
				if my documentControlCharacters is missing value then
					set controls to current application's NSMutableCharacterSet's characterSetWithRange:{location:0, |length|:9}
					controls's addCharactersInRange:{location:11, |length|:21}
					controls's addCharactersInRange:{location:127, |length|:1}
					set my documentControlCharacters to controls's |copy|()
				end if
				set isClean to (((theString's rangeOfCharacterFromSet:(my documentControlCharacters))'s location) as real) > 1.0E+18
				-- A lone surrogate cannot be UTF-8.
				set isClean to isClean and (theString's dataUsingEncoding:(current application's NSUTF8StringEncoding) allowLossyConversion:false) is not missing value
			end if
			if not isClean then
				set encodingError to findEncodingError()
				if encodingError is not missing value then
					raise(item 1 of encodingError, item 2 of encodingError, item 3 of encodingError)
				end if
				-- `id of` joins a lone high surrogate with the character after it, so only Foundation sees it.
				set surrogateError to findLoneSurrogate(theString)
				if surrogateError is not missing value then
					raise(item 1 of surrogateError, item 2 of surrogateError, item 3 of surrogateError)
				end if
			end if
		end checkCharacters

		-- The first lone surrogate in a string, as {reason, line, column}, or missing value. Its UTF-16 units are read as bytes, because Foundation's character sets do not match a lone surrogate.
		on findLoneSurrogate(theString)
			set theData to theString's dataUsingEncoding:(current application's NSUTF16LittleEndianStringEncoding)
			set my scanCodes to bytesOf(theData, 0, (theData's |length|()) as integer)
			set unitCount to (count my scanCodes) div 2
			set unitIndex to 0
			repeat while unitIndex < unitCount
				set unit to (item (unitIndex * 2 + 1) of my scanCodes) + (item (unitIndex * 2 + 2) of my scanCodes) * 256
				if unit ≥ 55296 and unit ≤ 57343 then
					set isPaired to false
					if unit < 56320 and unitIndex + 1 < unitCount then
						set nextUnit to (item (unitIndex * 2 + 3) of my scanCodes) + (item (unitIndex * 2 + 4) of my scanCodes) * 256
						set isPaired to nextUnit ≥ 56320 and nextUnit ≤ 57343
					end if
					if not isPaired then
						set prefixLines to splitText((theString's substringToIndex:unitIndex) as text, linefeed)
						set columnNumber to (count codePoints(item -1 of prefixLines)) + 1
						return {"A lone surrogate (" & formatCodePoint(unit) & ") is not a Unicode scalar value", count prefixLines, columnNumber}
					end if
					set unitIndex to unitIndex + 2
				else
					set unitIndex to unitIndex + 1
				end if
			end repeat
			return missing value
		end findLoneSurrogate

		on findEncodingError()
			if my pieceCount = 0 then
				return missing value
			end if
			set firstCodes to codePoints(item 1 of my pieces)
			if firstCodes is not {} and item 1 of firstCodes = 65279 then
				return {"A byte order mark (BOM) is not allowed", 1, 1}
			end if
			set surrogate to missing value
			-- The codes are in a property, because getting an item of a long list in a variable takes time in proportion to its length.
			repeat with theIndex from 1 to my pieceCount
				set my scanCodes to codePoints(item theIndex of my pieces)
				repeat with step from 1 to count my scanCodes
					set theCode to item step of my scanCodes
					if (theCode < 32 and theCode is not 9 and theCode is not 10) or theCode = 127 then
						if theCode = 13 then
							return {"A carriage return (U+000D) is not allowed anywhere. Use LF line endings", theIndex, step}
						end if
						return {controlReason(theCode), theIndex, step}
					else if theCode ≥ 55296 and theCode ≤ 57343 and surrogate is missing value then
						set surrogate to {"A lone surrogate (" & formatCodePoint(theCode) & ") is not a Unicode scalar value", theIndex, step}
					end if
				end repeat
			end repeat
			return surrogate
		end findEncodingError

		on controlReason(theCode)
			return "A raw control character (" & formatCodePoint(theCode) & ") is not allowed anywhere, including in strings and comments. In a string, write it as the escape \\u{" & lowercaseHex(theCode) & "} inside \"...\""
		end controlReason

		(*
		Skips spaces, tabs, line breaks, and comments, and returns whether a line break was crossed outside a block comment.
		*)
		on skipTrivia()
			set crossed to false
			-- The position is in a variable while it moves, which is faster than the property.
			set thePosition to my cursor
			repeat
				set theCode to item thePosition of my sourceCodes
				if theCode = 32 or theCode = 9 then
					set thePosition to thePosition + 1
				else if theCode = 10 then
					set crossed to true
					if thePosition < (count my sourceCodes) then
						set thePosition to thePosition + 1
					else
						loadLine((my lineIndex) + 1)
						set thePosition to 1
					end if
				else if theCode = 35 then
					set my cursor to thePosition
					skipLineComment()
					set thePosition to my cursor
				else if theCode = 47 and item (thePosition + 1) of my sourceCodes = 42 then
					set my cursor to thePosition
					skipBlockComment()
					set thePosition to my cursor
				else
					set my cursor to thePosition
					return crossed
				end if
			end repeat
		end skipTrivia

		-- The index after spaces and tabs on the current line, without crossing a line break.
		on skipHorizontalSpace(theIndex)
			repeat while isHorizontalSpaceCode(item theIndex of my sourceCodes)
				set theIndex to theIndex + 1
			end repeat
			return theIndex
		end skipHorizontalSpace

		-- The index after a bare key or keyword, shared by diagnostic lookahead.
		on skipBareKey(theIndex)
			repeat while isBareKeyCode(item theIndex of my sourceCodes)
				set theIndex to theIndex + 1
			end repeat
			return theIndex
		end skipBareKey

		-- A `#` comment runs to the line feed, which is the end of the piece when every piece is a line.
		on skipLineComment()
			if not my hasInnerLineBreak then
				set my cursor to count my sourceCodes
				return
			end if
			set theIndex to (my cursor) + 1
			repeat
				set theCode to item theIndex of my sourceCodes
				if theCode = 10 or theCode = -1 then
					exit repeat
				end if
				set theIndex to theIndex + 1
			end repeat
			set my cursor to theIndex
		end skipLineComment

		on skipBlockComment()
			set startLine to my lineIndex
			set startPosition to my cursor
			set nested to missing value
			set thePosition to (my cursor) + 2
			repeat
				set theCode to item thePosition of my sourceCodes
				if theCode = 42 and item (thePosition + 1) of my sourceCodes = 47 then
					exit repeat
				else if theCode = 47 and item (thePosition + 1) of my sourceCodes = 42 then
					-- An opening that overlaps the closing `*/`, as in `/*/`, is not inside the body.
					if item (thePosition + 2) of my sourceCodes = 47 then
						set thePosition to thePosition + 1
						exit repeat
					end if
					if nested is missing value then
						set nested to {my lineIndex, thePosition}
					end if
					set thePosition to thePosition + 1
				else if theCode = 10 then
					set my cursor to thePosition
					crossLineBreak()
					set thePosition to my cursor
				else if theCode = -1 then
					raise("Unterminated block comment", startLine, startPosition)
				else
					set thePosition to thePosition + 1
				end if
			end repeat
			if nested is not missing value then
				raise("Block comments cannot be nested, and their body may not contain “/*”", item 1 of nested, item 2 of nested)
			end if
			set my cursor to thePosition + 2
		end skipBlockComment

		on describeHere()
			return describeCode(item (my cursor) of my sourceCodes)
		end describeHere

		on slashCommentHint()
			if item (my cursor) of my sourceCodes = 47 and item ((my cursor) + 1) of my sourceCodes = 47 then
				return ". A comment starts with “#”"
			end if
			return ""
		end slashCommentHint

		(*
		The text of codes `firstIndex` to `lastIndex` of the current line.
		*)
		on sliceText(firstIndex, lastIndex)
			if lastIndex < firstIndex then
				return ""
			end if
			return string id (items firstIndex thru lastIndex of my sourceCodes)
		end sliceText

		-- Document

		(*
		Reads the document and returns its value. The records are made last, all at once, and read again with tagged objects where a record cannot hold the keys exactly.
		*)
		on readDocument()
			if my pieceCount = 0 then
				raise("A document must contain an object or an array, but this one is empty", 1, 1)
			end if
			if not my isChecked then
				checkCharacters()
			end if
			loadLine(1)
			skipTrivia()
			if item (my cursor) of my sourceCodes = -1 then
				fail("A document must contain an object or an array, but this one is empty")
			end if
			set theCode to item (my cursor) of my sourceCodes
			set startLine to my lineIndex
			set startPosition to my cursor
			if theCode = 123 then
				openCollection(2)
			else if theCode = 91 then
				openCollection(3)
			else
				openBareObject()
			end if
			try
				set theValue to readCollections()
			on error message number errorNumber from details
				if theCode is not 123 and theCode is not 91 and errorNumber is my invalidDocumentErrorNumber and not my hasEntry then
					diagnoseBareValue(startLine, startPosition)
				end if
				error message number errorNumber from details
			end try
			convertFloats()
			if not my madeRecord then
				return theValue
			end if
			if my isAllObjects then
				return readAgain(true, {})
			end if
			-- A record of every key shows the spelling that AppleScript keeps for each.
			set probeFields to {}
			repeat with theKey in my distinctKeys
				set end of probeFields to contents of theKey
				set end of probeFields to 0
			end repeat
			try
				if my distinctKeys = {} then
					return materializeRecords(theValue)
				end if
				set {probeRecord, theValue} to materializeRecords({{«class usrf»:probeFields}, theValue})
			on error number -2707
				-- AppleScript holds about 8,000 distinct labels in a process, and has no room for more, so the objects are tagged.
				return readAgain(true, {})
			end try
			set foundBadKeys to {}
			-- The second reading, which knows the keys that AppleScript does not keep, notes no keys, and its probe is an empty list.
			if my distinctKeys is not {} then
				repeat with theKey in respelledKeys(probeRecord, my distinctKeys)
					set end of foundBadKeys to codePoints(contents of theKey)
				end repeat
			end if
			if foundBadKeys is not {} then
				return readAgain(false, foundBadKeys)
			end if
			return theValue
		end readDocument

		on readAgain(allObjects, theBadKeys)
			set my isAllObjects to allObjects
			set my badKeys to theBadKeys
			set my frameKind to 0
			set my stack to {}
			set my stackDepth to 0
			set my depth to 0
			set my madeRecord to false
			set my hasEntry to false
			set my pendingFloats to {}
			set my distinctKeys to {}
			set my distinctCodes to {}
			set my keySet to missing value
			return readDocument()
		end readAgain

		(*
		Adds a key to the distinct keys of the document, marks the object when the key is one whose spelling AppleScript does not keep, and notes a key that starts with U+FEFF or U+FFFE.
		*)
		on noteKey(keyCodes)
			if keyCodes is not {} and item 1 of keyCodes is in {65279, 65534} then
				set my isAllObjects to true
			end if
			if my isAllObjects then
				return
			end if
			if my badKeys is not {} then
				if my badKeys contains {keyCodes} then
					set my frameHasBadKey to true
				end if
				return
			end if
			if my keySet is missing value then
				-- Small documents use native list membership, avoiding a bridge call for each key.
				if my distinctCodes contains {keyCodes} then
					return
				end if
				if (count my distinctCodes) < 128 then
					set end of my distinctCodes to keyCodes
				else
					set my keySet to current application's NSMutableSet's |set|()
					repeat with theKey in my distinctKeys
						my keySet's addObject:("x" & contents of theKey)
					end repeat
					set my distinctCodes to {}
				end if
			end if
			if my keySet is not missing value then
				-- Prefixing protects byte-order characters during AppleScriptObjC conversion.
				set exactKey to "x" & my frameKey
				if (my keySet's containsObject:exactKey) as boolean then
					return
				end if
				my keySet's addObject:exactKey
			end if
			set end of my distinctKeys to my frameKey
			if (count my distinctKeys) > my maximumDistinctKeys then
				set my isAllObjects to true
			end if
		end noteKey

		(*
		A whole document that is one scalar, such as `5` or an instant, fails as an entry. That failure is reported as what it is.
		*)
		on diagnoseBareValue(startLine, startPosition)
			-- The floats read before the error keep their priority over it.
			set savedFloats to my pendingFloats
			set my pendingFloats to {}
			set my frameKind to 3
			set my frameItems to {}
			loadLine(startLine)
			set my cursor to startPosition
			try
				set end of my frameItems to readScalar()
				convertFloats()
				skipTrivia()
				set isBareValue to item (my cursor) of my sourceCodes = -1
			on error number 1
				set isBareValue to false
			end try
			set my pendingFloats to savedFloats
			if isBareValue then
				raise("A bare value is not a document. A document is an object or an array, so write it as `key: value` or `[value]`", startLine, startPosition)
			end if
		end diagnoseBareValue

		on openBareObject()
			set my depth to 1
			resetFrame(1)
		end openBareObject

		-- Initializes the frame for either a bare object or a bracketed collection.
		on resetFrame(theKind)
			set my frameKind to theKind
			set my frameItems to {}
			set my frameBlocks to {}
			set my frameLine to my lineIndex
			set my framePosition to my cursor
			set my frameFolded to {}
			set my frameExact to {}
			set my frameKeySets to missing value
			set my frameCollides to false
			set my frameHasBadKey to false
			set my frameKey to missing value
		end resetFrame

		on openCollection(theKind)
			if (my depth) + 1 > maximumDepth then
				fail("The document is nested more than " & maximumDepth & " levels deep")
			end if
			if my frameKind is not 0 then
				-- The frame is stored without a variable, which would copy the lists in it.
				set my stackDepth to (my stackDepth) + 1
				if my stackDepth > (count my stack) then
					set end of my stack to missing value
				end if
				set item (my stackDepth) of my stack to {my frameKind, my frameItems, my frameBlocks, my frameLine, my framePosition, my frameFolded, my frameExact, my frameKeySets, my frameCollides, my frameKey, my frameKeyCodes, my frameKeyFolded, my frameKeyLine, my frameKeyPosition, my frameHasBadKey}
			end if
			set my depth to (my depth) + 1
			resetFrame(theKind)
			set my cursor to (my cursor) + 1
			skipTrivia()
		end openCollection

		(*
		Reads members and items until the document's collection is closed, and returns its value. Collections are kept on a stack rather than read by recursion, because AppleScript runs out of stack at a few hundred nested handler calls.
		*)
		on readCollections()
			-- Whether the frame expects a member or an item, rather than what follows one.
			set isExpectingItem to true
			repeat
				set theKind to my frameKind
				if isExpectingItem then
					if theKind = 3 then
						set closing to 93
					else
						set closing to 125
					end if
					set theCode to item (my cursor) of my sourceCodes
					if theKind is not 1 and theCode = closing then
						set closedValue to closeCollection()
						if my frameKind = 0 then
							skipTrivia()
							if item (my cursor) of my sourceCodes is not -1 then
								fail("Unexpected " & describeHere() & " after the end of the document")
							end if
							return closedValue
						end if
						addValue(closedValue)
						set isExpectingItem to false
					else if theKind is not 1 and theCode = -1 then
						failUnterminated()
					else
						if theKind is not 3 then
							readKeyAndColon()
						end if
						set theCode to item (my cursor) of my sourceCodes
						if theCode = 123 then
							openCollection(2)
						else if theCode = 91 then
							openCollection(3)
						else
							addValue(readScalar())
							set isExpectingItem to false
						end if
					end if
				else
					set isExpectingItem to readSeparator()
					if not isExpectingItem and my frameKind = 1 then
						return closeCollection()
					end if
				end if
			end repeat
		end readCollections

		(*
		After a member or an item: reads the separator and returns true when another member or item, or the closing bracket, follows. For an object without braces, returns false at the end of the document.
		*)
		on readSeparator()
			set itemEndLine to my lineIndex
			set hasLineBreak to skipTrivia()
			set theCode to item (my cursor) of my sourceCodes
			set theKind to my frameKind
			if theKind = 1 then
				if theCode = -1 then
					return false
				end if
				if theCode = 44 then
					fail("Top-level entries are separated by line breaks, not commas. Use braces for a one-line object")
				end if
				if not hasLineBreak then
					fail("Expected a line break before the next entry, but found " & describeHere() & slashCommentHint())
				end if
				return true
			end if
			if theKind = 3 then
				set closing to 93
			else
				set closing to 125
			end if
			if theCode = -1 then
				failUnterminated()
			end if
			if theCode = 44 then
				if hasLineBreak then
					fail("A comma must be on the same line as the item before it. The line break already separates the items, so remove the comma")
				end if
				set my cursor to (my cursor) + 1
				skipTrivia()
				return true
			end if
			if not hasLineBreak and theCode is not closing then
				if theKind = 3 then
					set itemName to "an array item"
				else
					set itemName to "an object member"
				end if
				set hint to slashCommentHint()
				if my lineIndex is not itemEndLine then
					set hint to ". A line break inside a block comment does not separate items"
				end if
				fail("Expected “,”, a line break, or “" & textFromCodes({closing}) & "” after " & itemName & ", but found " & describeHere() & hint)
			end if
			return true
		end readSeparator

		on failUnterminated()
			if my frameKind = 2 then
				raise("Unterminated object: expected “}”", my frameLine, my framePosition)
			end if
			raise("Unterminated array: expected “]”", my frameLine, my framePosition)
		end failUnterminated

		(*
		Adds a finished value to the collection being read. A member's key is checked for duplicates only after its value, as the value's own errors come first.
		*)
		on addValue(theValue)
			if my frameKind = 1 then
				set my hasEntry to true
			end if
			if my frameKind is not 3 then
				registerKey()
				set end of my frameItems to my frameKey
				set my frameKey to missing value
			end if
			set end of my frameItems to theValue
			if (count my frameItems) ≥ 2000 then
				set end of my frameBlocks to my frameItems
				set my frameItems to {}
			end if
		end addValue

		(*
		Raises “Duplicate key” for a key that the object has already. AppleScript matches record labels ignoring ASCII letter case, so keys that differ only in that are recorded, to make the object a tagged one. An object with many keys uses exact string membership sets, so case-variant groups need no pairwise scan.
		*)
		on registerKey()
			set keyCodes to my frameKeyCodes
			set folded to my frameKeyFolded
			noteKey(keyCodes)
			if my frameKeySets is missing value and (count my frameFolded) ≥ 256 then
				set my frameKeySets to {current application's NSMutableSet's |set|(), current application's NSMutableSet's |set|()}
				repeat with theIndex from 1 to count my frameFolded
					(item 1 of my frameKeySets)'s addObject:("x" & textFromCodes(item theIndex of my frameFolded))
					(item 2 of my frameKeySets)'s addObject:("x" & textFromCodes(item theIndex of my frameExact))
				end repeat
				set my frameFolded to {}
				set my frameExact to {}
			end if
			if my frameKeySets is missing value then
				-- `contains` compares the code points natively, which is much faster than a loop.
				if my frameFolded contains {folded} then
					if my frameExact contains {keyCodes} then
						raise("Duplicate key " & describeKey(my frameKey), my frameKeyLine, my frameKeyPosition)
					end if
					set my frameCollides to true
				end if
				set end of my frameFolded to folded
				set end of my frameExact to keyCodes
			else
				-- Prefixing protects leading byte-order characters during AppleScriptObjC conversion.
				set exactKey to "x" & my frameKey
				set foldedKey to "x" & textFromCodes(folded)
				if ((item 2 of my frameKeySets)'s containsObject:exactKey) as boolean then
					raise("Duplicate key " & describeKey(my frameKey), my frameKeyLine, my frameKeyPosition)
				end if
				if ((item 1 of my frameKeySets)'s containsObject:foldedKey) as boolean then
					set my frameCollides to true
				end if
				(item 1 of my frameKeySets)'s addObject:foldedKey
				(item 2 of my frameKeySets)'s addObject:exactKey
			end if
		end registerKey


		on closeCollection()
			set theKind to my frameKind
			set theItems to my frameItems
			if my frameBlocks is not {} then
				-- Joining blocks makes a new list, so floats that point into the blocks are converted first.
				convertFloats()
				script Joiner
					property joinedItems : {}
				end script
				-- Each item is added to a list in a property, because joining long lists copies them.
				repeat with blockIndex from 1 to count my frameBlocks
					repeat with step from 1 to count item blockIndex of my frameBlocks
						set end of Joiner's joinedItems to item step of item blockIndex of my frameBlocks
					end repeat
				end repeat
				repeat with step from 1 to count my frameItems
					set end of Joiner's joinedItems to item step of my frameItems
				end repeat
				set theItems to Joiner's joinedItems
			end if
			if theKind is not 1 then
				set my cursor to (my cursor) + 1
			end if
			if theKind = 3 then
				set theValue to theItems
			else if my frameCollides or my frameHasBadKey or my isAllObjects or theItems = {} then
				convertFloats()
				script Store
					property source : theItems
					property pairs : {}
				end script
				repeat with theIndex from 1 to (count Store's source) by 2
					set end of Store's pairs to {item theIndex of Store's source, item (theIndex + 1) of Store's source}
				end repeat
				set theValue to {class:«class SOMo», entries:Store's pairs}
			else
				set my madeRecord to true
				set theValue to {«class usrf»:theItems}
			end if
			set my depth to (my depth) - 1
			set theDepth to my stackDepth
			if theDepth = 0 then
				set my frameKind to 0
			else
				set my frameKind to item 1 of item theDepth of my stack
				set my frameItems to item 2 of item theDepth of my stack
				set my frameBlocks to item 3 of item theDepth of my stack
				set my frameLine to item 4 of item theDepth of my stack
				set my framePosition to item 5 of item theDepth of my stack
				set my frameFolded to item 6 of item theDepth of my stack
				set my frameExact to item 7 of item theDepth of my stack
				set my frameKeySets to item 8 of item theDepth of my stack
				set my frameCollides to item 9 of item theDepth of my stack
				set my frameKey to item 10 of item theDepth of my stack
				set my frameKeyCodes to item 11 of item theDepth of my stack
				set my frameKeyFolded to item 12 of item theDepth of my stack
				set my frameKeyLine to item 13 of item theDepth of my stack
				set my frameKeyPosition to item 14 of item theDepth of my stack
				set my frameHasBadKey to item 15 of item theDepth of my stack
				set item theDepth of my stack to missing value
				set my stackDepth to theDepth - 1
			end if
			return theValue
		end closeCollection

		-- Keys

		(*
		Reads a key and its `:`, and the whitespace after it.
		*)
		on readKeyAndColon()
			set keyLine to my lineIndex
			set keyStart to my cursor
			set theCode to item keyStart of my sourceCodes
			if theCode = 39 or theCode = 34 then
				if item (keyStart + 1) of my sourceCodes = theCode and item (keyStart + 2) of my sourceCodes = theCode then
					fail("A block string cannot be a key")
				end if
				if theCode = 39 then
					set keyCodes to readLiteralCodes()
				else
					set keyCodes to readEscapedCodes()
				end if
				set folded to foldCase(keyCodes)
			else
				set theIndex to keyStart
				set hasUppercase to false
				repeat
					set theCode to item theIndex of my sourceCodes
					if theCode ≥ 97 then
						if theCode > 122 then
							exit repeat
						end if
					else if theCode ≥ 65 and theCode ≤ 90 then
						set hasUppercase to true
					else if not ((theCode ≥ 48 and theCode ≤ 57) or theCode = 95 or theCode = 45) then
						exit repeat
					end if
					set theIndex to theIndex + 1
				end repeat
				if theIndex = keyStart then
					failExpectedKey()
				end if
				set keyCodes to items keyStart thru (theIndex - 1) of my sourceCodes
				if hasUppercase then
					set folded to foldCase(keyCodes)
				else
					set folded to keyCodes
				end if
				set my cursor to theIndex
			end if
			set theCode to item (my cursor) of my sourceCodes
			if theCode = 46 then
				failDotInKey(keyStart)
			end if
			if theCode is not 58 then
				failMissingColon(keyLine, keyStart)
			end if
			-- A bare-key character right after the `:`, rather than the usual space, may make it part of the key.
			set afterColon to item ((my cursor) + 1) of my sourceCodes
			if afterColon > 44 then
				if isBareKeyCode(afterColon) and isBareKeyCode(item keyStart of my sourceCodes) then
					diagnoseKeyWithColon(keyStart)
				end if
			end if
			set my frameKey to textFromCodes(keyCodes)
			set my frameKeyCodes to keyCodes
			set my frameKeyFolded to folded
			set my frameKeyLine to keyLine
			set my frameKeyPosition to keyStart
			set my cursor to (my cursor) + 1
			-- The usual space after the `:` is skipped here.
			if afterColon = 32 then
				set my cursor to (my cursor) + 1
				if item (my cursor) of my sourceCodes is not in {32, 9, 10, 35, 47, -1} then
					return
				end if
			end if
			if skipTrivia() then
				diagnoseKeyAsValue()
			end if
		end readKeyAndColon

		(*
		A bare key followed directly by `:` and more of a key, up to a `:` that ends the key, as in `a:b: 1`. Such a document is never valid.
		*)
		on diagnoseKeyWithColon(keyStart)
			set theIndex to keyStart
			repeat
				set theCode to item theIndex of my sourceCodes
				if theCode = 58 then
					set nextCode to item (theIndex + 1) of my sourceCodes
					if nextCode is in {10, 32, 9, -1} then
						raise("A key that contains “:” must be quoted, as in '" & abbreviate(sliceText(keyStart, theIndex - 1), 40) & "'", my lineIndex, keyStart)
					end if
				else if not isBareKeyCode(theCode) then
					return
				end if
				set theIndex to theIndex + 1
			end repeat
		end diagnoseKeyWithColon

		on failExpectedKey()
			set theCode to item (my cursor) of my sourceCodes
			if theCode = -1 then
				fail("Expected a key")
			end if
			set hint to ""
			if isQuotableKeyCode(theCode) then
				set hint to ". A key that contains characters other than letters, digits, “_”, and “-” must be quoted"
				-- The run of characters that a quoted key could hold, up to its `:`, is the example.
				set theIndex to my cursor
				repeat while theIndex - (my cursor) < 1000 and isQuotableKeyCode(item theIndex of my sourceCodes)
					set theIndex to theIndex + 1
				end repeat
				if item theIndex of my sourceCodes = 58 then
					set hint to hint & ", as in '" & abbreviate(sliceText(my cursor, theIndex - 1), 40) & "'"
				end if
			end if
			fail("Expected a key, but found " & describeHere() & hint & slashCommentHint())
		end failExpectedKey

		on failDotInKey(keyStart)
			set theIndex to keyStart
			repeat while isBareKeyCode(item theIndex of my sourceCodes) or item theIndex of my sourceCodes = 46
				set theIndex to theIndex + 1
			end repeat
			set isBareStart to isBareKeyCode(item keyStart of my sourceCodes)
			set hasEmptyWord to false
			set previous to 46
			repeat with step from keyStart to theIndex - 1
				set theCode to item step of my sourceCodes
				if theCode = 46 and previous = 46 then
					set hasEmptyWord to true
				end if
				set previous to theCode
			end repeat
			if previous = 46 then
				set hasEmptyWord to true
			end if
			if item theIndex of my sourceCodes is not 58 or not isBareStart or hasEmptyWord then
				fail("A key cannot contain “.” unless it is quoted. Quote the whole key, or use braces to nest, as in a: {b: …}")
			end if
			-- Every example is abbreviated to 40 characters, so diagnostic construction needs only the first 41.
			set previewEnd to theIndex - 1
			if previewEnd > keyStart + 40 then
				set previewEnd to keyStart + 40
			end if
			set keyText to sliceText(keyStart, previewEnd)
			set keyWords to splitText(keyText, ".")
			set nested to joinTexts(keyWords, ": {") & ": …"
			repeat (count keyWords) - 1 times
				set nested to nested & "}"
			end repeat
			fail("A bare key cannot contain “.”. Quote it, as in '" & abbreviate(keyText, 40) & "', or use braces to nest, as in " & abbreviate(nested, 40))
		end failDotInKey

		on failMissingColon(keyLine, keyStart)
			set nextIndex to skipHorizontalSpace(my cursor)
			set nextCode to item nextIndex of my sourceCodes
			if nextCode = 58 and nextIndex > my cursor then
				fail("Whitespace is not allowed between a key and its “:”")
			end if
			if nextCode = 47 and item (nextIndex + 1) of my sourceCodes = 42 then
				set theIndex to nextIndex + 2
				repeat
					set theCode to item theIndex of my sourceCodes
					if theCode = 10 or theCode = -1 then
						exit repeat
					end if
					if theCode = 42 and item (theIndex + 1) of my sourceCodes = 47 then
						set afterIndex to skipHorizontalSpace(theIndex + 2)
						if item afterIndex of my sourceCodes = 58 then
							raise("A comment is not allowed between a key and its “:”", my lineIndex, nextIndex)
						end if
						exit repeat
					end if
					set theIndex to theIndex + 1
				end repeat
			end if
			-- A bare key with a space in it, such as `the name: 1`.
			set lastKeyCode to item ((my cursor) - 1) of my sourceCodes
			if nextIndex > my cursor and isBareKeyCode(nextCode) and lastKeyCode is not 39 and lastKeyCode is not 34 then
				set theIndex to nextIndex
				set isWords to true
				repeat
					set theCode to item theIndex of my sourceCodes
					if theCode = 58 or theCode = 10 or theCode = -1 then
						exit repeat
					end if
					if not (isBareKeyCode(theCode) or theCode = 32 or theCode = 9) then
						set isWords to false
						exit repeat
					end if
					set theIndex to theIndex + 1
				end repeat
				set afterColon to 0
				if item theIndex of my sourceCodes = 58 then
					set afterColon to item (theIndex + 1) of my sourceCodes
				end if
				if item theIndex of my sourceCodes = 58 and isWords and afterColon is in {32, 9, 10, -1} then
					set keyEnd to theIndex - 1
					repeat while isHorizontalSpaceCode(item keyEnd of my sourceCodes)
						set keyEnd to keyEnd - 1
					end repeat
					raise("A bare key cannot contain spaces. Quote it, as in '" & abbreviate(sliceText(keyStart, keyEnd), 40) & "'", keyLine, keyStart)
				end if
			end if
			set theCode to item (my cursor) of my sourceCodes
			if theCode = -1 or theCode = 10 then
				fail("Expected “:” after the key")
			end if
			set previousCode to item ((my cursor) - 1) of my sourceCodes
			set hint to ""
			if previousCode is not 39 and previousCode is not 34 and nextIndex = my cursor and isQuotableKeyCode(nextCode) then
				set hint to ". A key that contains characters other than letters, digits, “_”, and “-” must be quoted"
			end if
			set my cursor to nextIndex
			fail("Expected “:” after the key, but found " & describeHere() & hint)
		end failMissingColon

		-- Whether a character can be in a key that is quoted for it, for a hint: not invisible, not whitespace, and not a character with a meaning, such as `:` or `#`.
		on isQuotableKeyCode(theCode)
			if theCode is in {-1, 9, 10, 32, 34, 35, 39, 42, 44, 47, 58, 61, 91, 93, 123, 125} or theCode is in my namedWhitespace then
				return false
			end if
			return not isInvisibleCode(theCode)
		end isQuotableKeyCode

		(*
		An entry whose value was left out, followed by another entry on the next line, as in `a:` and then `b: 1`, reads the next key as the value.
		*)
		on diagnoseKeyAsValue()
			set startIndex to my cursor
			set theCode to item startIndex of my sourceCodes
			-- A YAML block sequence.
			if theCode = 45 and (item (startIndex + 1) of my sourceCodes = 32 or item (startIndex + 1) of my sourceCodes = 9) then
				fail("Expected a value, but found a “-” list. An array is written in brackets, as in [80, 443]")
			end if
			set theIndex to startIndex
			if theCode = 39 or theCode = 34 then
				-- A quoted key cannot be part of a value, so anything may follow its `:`.
				try
					if theCode = 39 then
						set keyCodes to readLiteralCodes()
					else
						set keyCodes to readEscapedCodes()
					end if
					set isKey to item (my cursor) of my sourceCodes = 58
				on error number 1
					set isKey to false
				end try
				set my cursor to startIndex
				if isKey then
					fail("Expected a value, but found the key " & describeKey(textFromCodes(keyCodes)))
				end if
				return
			end if
			set theIndex to skipBareKey(theIndex)
			if theIndex = startIndex or item theIndex of my sourceCodes is not 58 then
				return
			end if
			set nextCode to item (theIndex + 1) of my sourceCodes
			if nextCode is in {10, 32, 9, -1} then
				fail("Expected a value, but found the key " & describeKey(sliceText(startIndex, theIndex - 1)))
			end if
		end diagnoseKeyAsValue

		-- Scalars

		on readScalar()
			set startIndex to my cursor
			set theCode to item startIndex of my sourceCodes
			if theCode = 39 or theCode = 34 then
				if item (startIndex + 1) of my sourceCodes = theCode and item (startIndex + 2) of my sourceCodes = theCode then
					set theValue to readBlockString(theCode)
				else if theCode = 39 then
					set theValue to textFromCodes(readLiteralCodes())
				else
					set theValue to readEscapedText()
				end if
				if hasByteOrderPrefix(theValue) then
					set my isAllObjects to true
				end if
				checkValueEnd(startIndex, false)
				return theValue
			end if
			-- An instant has a “-” after four digits, and the codes of a line end with a line feed or -1 after it.
			if theCode ≥ 48 and theCode ≤ 57 and startIndex + 19 < (count my sourceCodes) then
				if item (startIndex + 4) of my sourceCodes = 45 then
					set theValue to readUTCInstant()
					if theValue is not missing value then
						checkValueEnd(startIndex, true)
						return theValue
					end if
				end if
			end if
			if theCode = 45 or (theCode ≥ 48 and theCode ≤ 57) then
				set theValue to readPlainNumber()
				if theValue is not missing value then
					if isHorizontalSpaceCode(item (my cursor) of my sourceCodes) then
						diagnoseUnitAfterSpace(startIndex)
					end if
					return theValue
				end if
			end if
			if theCode = 116 and isKeyword({116, 114, 117, 101}) then
				set theValue to true
			else if theCode = 102 and isKeyword({102, 97, 108, 115, 101}) then
				set theValue to false
			else if theCode = 110 and isKeyword({110, 117, 108, 108}) then
				set theValue to missing value
			else if theCode = 105 and isKeyword({105, 110, 102, 105, 110, 105, 116, 121}) then
				set theValue to item 1 of infinities()
			else if theCode = 45 and isKeyword({45, 105, 110, 102, 105, 110, 105, 116, 121}) then
				set theValue to item 2 of infinities()
			else if theCode = 45 or (theCode ≥ 48 and theCode ≤ 57) then
				set theValue to readNumberToken()
				checkValueEnd(startIndex, true)
				return theValue
			else
				failUnexpectedValue()
			end if
			checkValueEnd(startIndex, false)
			return theValue
		end readScalar

		(*
		The common case, a decimal int in AppleScript's range or a float without an exponent, such as `8080`, `-3`, or `30.5`, without the general path's scan and classification. Returns missing value for anything else, including every error, which the general path handles.
		*)
		on readPlainNumber()
			set startIndex to my cursor
			set theIndex to startIndex
			set isNegative to item theIndex of my sourceCodes = 45
			if isNegative then
				set theIndex to theIndex + 1
			end if
			set integerStart to theIndex
			set theValue to 0
			repeat
				set theCode to item theIndex of my sourceCodes
				if theCode < 48 or theCode > 57 then
					exit repeat
				end if
				-- The digit's value is added in one step, so that the sum never passes AppleScript's integer range, which would make it a real.
				set theValue to theValue * 10 + (theCode - 48)
				set theIndex to theIndex + 1
				if theIndex - integerStart > 9 then
					return missing value
				end if
			end repeat
			set integerLength to theIndex - integerStart
			-- No digits, or a leading zero followed by more digits. The loop has already left on a tenth digit.
			if integerLength = 0 or (integerLength > 1 and item integerStart of my sourceCodes = 48) then
				return missing value
			end if
			set isFloat to theCode = 46
			if isFloat then
				set fractionStart to theIndex + 1
				set theIndex to fractionStart
				repeat
					set theCode to item theIndex of my sourceCodes
					if theCode < 48 or theCode > 57 then
						exit repeat
					end if
					set theIndex to theIndex + 1
				end repeat
				if theIndex = fractionStart then
					return missing value
				end if
			end if
			-- A character that may continue a number, such as `e`, `_`, or a unit, needs the general path.
			if not isValueEndCode(theCode) then
				return missing value
			end if
			if isFloat then
				set theText to string id (items startIndex thru (theIndex - 1) of my sourceCodes)
				set my cursor to theIndex
				return deferFloat(theText, theText, my lineIndex, startIndex)
			end if
			if isNegative then
				-- `-0` is an error, which the general path reports.
				if theValue = 0 then
					return missing value
				end if
				set theValue to -theValue
			end if
			if theValue < my smallestInteger or theValue > my largestInteger then
				return missing value
			end if
			set my cursor to theIndex
			return theValue as integer
		end readPlainNumber

		(*
		The common case of an instant, in UTC and in canonical form, such as `2026-10-10T16:25:41.111Z`, without the general path's scan and classification. Returns missing value for anything else, which the general path reads. The caller checks that the line has room for the instant and the code after it.
		*)
		on readUTCInstant()
			set startIndex to my cursor
			set endIndex to startIndex + 19
			if item endIndex of my sourceCodes = 46 then
				repeat
					set endIndex to endIndex + 1
					set theCode to item endIndex of my sourceCodes
					if theCode < 48 or theCode > 57 then
						exit repeat
					end if
					if endIndex - startIndex > 28 then
						return missing value
					end if
				end repeat
				if endIndex ≥ (count my sourceCodes) then
					return missing value
				end if
			end if
			-- A character that may continue the token, such as a letter, needs the general path.
			if not isValueEndCode(item (endIndex + 1) of my sourceCodes) then
				return missing value
			end if
			set theText to canonicalUTCInstant(items startIndex thru endIndex of my sourceCodes)
			if theText is missing value then
				return missing value
			end if
			set my cursor to endIndex + 1
			return {class:«class SOMt», value:theText}
		end readUTCInstant

		(*
		A float is converted later, in a batch with the others, so its place in the collection being read is kept. Returns the placeholder.
		*)
		on deferFloat(theText, tokenText, atLine, atPosition)
			-- In an object, the key comes first.
			set itemOffset to 2
			if my frameKind is 3 then
				set itemOffset to 1
			end if
			set end of my pendingFloats to {my frameItems, (count my frameItems) + itemOffset, theText, atLine, atPosition, tokenText}
			return 0.0
		end deferFloat

		on infinities()
			if my cachedInfinities is missing value then
				set my cachedInfinities to callJavaScript(floatJavaScriptContext(), "somlInfinities", "(function () { return [Infinity, -Infinity]; })", {})
			end if
			return my cachedInfinities
		end infinities

		on isKeyword(wordCodes)
			set startIndex to my cursor
			set wordLength to count wordCodes
			if startIndex + wordLength > (count my sourceCodes) then
				return false
			end if
			if (items startIndex thru (startIndex + wordLength - 1) of my sourceCodes) is not wordCodes then
				return false
			end if
			set nextCode to item (startIndex + wordLength) of my sourceCodes
			if isBareKeyCode(nextCode) then
				return false
			end if
			set my cursor to startIndex + wordLength
			return true
		end isKeyword

		on checkValueEnd(startIndex, isNumber)
			set theCode to item (my cursor) of my sourceCodes
			if isValueEndCode(theCode) then
				if isNumber and isHorizontalSpaceCode(theCode) then
					diagnoseUnitAfterSpace(startIndex)
				end if
				return
			end if
			if isNumber and (theCode = 181 or theCode = 956) and item ((my cursor) + 1) of my sourceCodes = 115 then
				-- The duration is only suggested when it is valid.
				set numberText to sliceText(startIndex, (my cursor) - 1)
				if isValidDuration(numberText & "us") then
					fail("The unit for microseconds is written us, as in " & abbreviate(numberText, 40) & "us")
				end if
				fail("The unit for microseconds is written us")
			end if
			if theCode = 39 and item startIndex of my sourceCodes = 39 then
				fail("There is no '' escape in a '...' string. Write a string that contains ' as \"...\", as in \"it's\"")
			end if
			fail("Unexpected " & describeHere() & " after a value")
		end checkValueEnd

		(*
		A number followed by a space and a word, such as `512 MiB` or `10 seconds`.
		*)
		on diagnoseUnitAfterSpace(startIndex)
			set unitStart to skipHorizontalSpace(my cursor)
			set unitEnd to unitStart
			repeat
				set theCode to item unitEnd of my sourceCodes
				if isLetterCode(theCode) then
					set unitEnd to unitEnd + 1
				else
					exit repeat
				end if
			end repeat
			if unitEnd = unitStart then
				return
			end if
			set afterIndex to skipHorizontalSpace(unitEnd)
			set afterCode to item afterIndex of my sourceCodes
			if afterCode is not in {10, 44, 93, 125, 35, -1} and not (afterCode = 47 and item (afterIndex + 1) of my sourceCodes is in {42, 47}) then
				return
			end if
			set unit to sliceText(unitStart, unitEnd - 1)
			considering case, diacriticals, hyphens, punctuation and white space
				if unit is in {"true", "false", "null", "infinity"} then
					return
				end if
			end considering
			set numberText to sliceText(startIndex, (my cursor) - 1)
			set duration to "10s"
			considering case, diacriticals, hyphens, punctuation and white space
				if unit is in {"h", "m", "s", "ms", "us", "ns"} and isValidDuration(numberText & unit) then
					set duration to numberText & unit
				end if
			end considering
			raise("A unit cannot follow a number after a space. Write a duration without the space, as in " & duration & ", and anything else, such as a size, as a string, as in '" & abbreviate(numberText & " " & unit, 40) & "'", my lineIndex, unitStart)
		end diagnoseUnitAfterSpace

		on isValidDuration(theText)
			try
				durationParts(theText)
				return true
			on error number 1
				return false
			end try
		end isValidDuration

		on failUnexpectedValue()
			set theCode to item (my cursor) of my sourceCodes
			if theCode = -1 then
				fail("Expected a value, but reached the end of the document")
			end if
			if theCode = 43 then
				fail("A “+” sign is not allowed. A number without a sign is positive")
			end if
			if theCode = 46 and isDigitCode(item ((my cursor) + 1) of my sourceCodes) then
				fail("A number cannot begin with “.”; write a digit before it, as in 0.5")
			end if
			set theIndex to skipBareKey(my cursor)
			if theIndex > my cursor then
				set wordText to sliceText(my cursor, theIndex - 1)
				if item theIndex of my sourceCodes = 58 then
					fail("Expected a value, but found the key " & abbreviate(wordText, 40))
				end if
				fail(describeUnknownWord(wordText, unquotedText(my cursor)))
			end if
			if theCode = 124 then
				set nextIndex to (my cursor) + 1
				if item nextIndex of my sourceCodes is in {45, 43} then
					set nextIndex to nextIndex + 1
				end if
				set nextIndex to skipHorizontalSpace(nextIndex)
				if item nextIndex of my sourceCodes is in {10, -1} then
					fail("Expected a value, but found “|”. Write a multiline string as a block string, between ''' lines")
				end if
			end if
			fail("Expected a value, but found " & describeHere() & slashCommentHint())
		end failUnexpectedValue

		(*
		The text from `startIndex` that was most likely meant as one unquoted string: up to the end of the line, a comma, a closing bracket, or a comment after a space.
		*)
		on unquotedText(startIndex)
			set theIndex to startIndex
			repeat
				set theCode to item theIndex of my sourceCodes
				if theCode is in {10, -1, 44, 93, 125} then
					exit repeat
				end if
				if (theCode = 35 or (theCode = 47 and item (theIndex + 1) of my sourceCodes = 42)) and theIndex > startIndex and isHorizontalSpaceCode(item (theIndex - 1) of my sourceCodes) then
					exit repeat
				end if
				set theIndex to theIndex + 1
			end repeat
			repeat while theIndex > startIndex and isHorizontalSpaceCode(item (theIndex - 1) of my sourceCodes)
				set theIndex to theIndex - 1
			end repeat
			return sliceText(startIndex, theIndex - 1)
		end unquotedText

		on describeUnknownWord(wordText, fullText)
			set lowercase to ""
			-- Every keyword covered by these hints fits in nine ASCII characters.
			if length of wordText ≤ 9 and length of fullText ≤ 9 then
				set wordCodes to codePoints(wordText)
				if codePoints(fullText) = wordCodes then
					set lowercase to textFromCodes(foldCase(wordCodes))
				end if
			end if
			considering case, diacriticals, hyphens, punctuation and white space
				if lowercase is in {"true", "false", "yes", "no", "on", "off"} then
					return "“" & wordText & "” is not a value. Booleans are written true and false, in lowercase"
				end if
				if lowercase is in {"null", "nil", "none", "undefined"} then
					return "“" & wordText & "” is not a value. Null is written null, in lowercase"
				end if
				if lowercase = "nan" then
					return "NaN is not representable. Use null for a missing value"
				end if
				if lowercase is in {"inf", "infinity"} then
					return "“" & wordText & "” is not a value. Infinity is written infinity, in lowercase"
				end if
			end considering
			return "Unexpected “" & abbreviate(wordText, 40) & "”. A string value must be quoted" & quotingExample(fullText)
		end describeUnknownWord

		on quotingExample(theText)
			considering case, diacriticals, hyphens, punctuation and white space
				if theText contains "'" then
					return ""
				end if
			end considering
			return ", as in '" & abbreviate(theText, 40) & "'"
		end quotingExample

		-- Strings

		(*
		A '...' string, from its opening quote. Returns the code points of its value.
		*)
		on readLiteralCodes()
			set startIndex to my cursor
			set theIndex to startIndex + 1
			repeat
				set theCode to item theIndex of my sourceCodes
				if theCode = 39 then
					exit repeat
				end if
				-- A tab is the only code below 11 that a string holds, and a line feed and the end of the document, -1, end it.
				if theCode < 11 and theCode is not 9 then
					raise("Unterminated string. A '...' string must end on the line it starts on; use a block string (''') for multiple lines", my lineIndex, startIndex)
				end if
				set theIndex to theIndex + 1
			end repeat
			set my cursor to theIndex + 1
			if theIndex = startIndex + 1 then
				return {}
			end if
			return items (startIndex + 1) thru (theIndex - 1) of my sourceCodes
		end readLiteralCodes

		-- A "..." string, from its opening quote. Returns the code points of its value, for a key.
		on readEscapedCodes()
			return codePoints(readEscapedText())
		end readEscapedCodes

		(*
		A "..." string, from its opening quote. Returns its value. The parts between escapes are joined as text, because joining lists of code points copies them for every escape.
		*)
		on readEscapedText()
			set startIndex to my cursor
			set theIndex to startIndex + 1
			set chunkStart to theIndex
			-- The parts are in a property, because a long list in a variable is slow.
			script Store
				property parts : {}
			end script
			repeat
				set theCode to item theIndex of my sourceCodes
				if theCode = 34 then
					exit repeat
				end if
				if theCode < 11 and theCode is not 9 then
					raise("Unterminated string. A \"...\" string must end on the line it starts on; use a block string (\"\"\") for multiple lines", my lineIndex, startIndex)
				end if
				if theCode = 92 then
					if theIndex > chunkStart then
						set end of Store's parts to string id (items chunkStart thru (theIndex - 1) of my sourceCodes)
					end if
					set {escapedCode, theIndex} to readEscape(theIndex)
					set end of Store's parts to textFromCodes({escapedCode})
					set chunkStart to theIndex
				else
					set theIndex to theIndex + 1
				end if
			end repeat
			set my cursor to theIndex + 1
			if chunkStart = startIndex + 1 then
				return sliceText(chunkStart, theIndex - 1)
			end if
			if theIndex > chunkStart then
				set end of Store's parts to string id (items chunkStart thru (theIndex - 1) of my sourceCodes)
			end if
			return joinTexts(Store's parts, "")
		end readEscapedText

		(*
		Decodes the escape at `theIndex`, a backslash. Returns the code point and the index after the escape.
		*)
		on readEscape(theIndex)
			set theCode to item (theIndex + 1) of my sourceCodes
			if theCode = 92 then
				return {92, theIndex + 2}
			else if theCode = 34 then
				return {34, theIndex + 2}
			else if theCode = 110 then
				return {10, theIndex + 2}
			else if theCode = 116 then
				return {9, theIndex + 2}
			else if theCode = 117 then
				return readUnicodeEscape(theIndex)
			else if theCode = 114 then
				raise("There is no \\r escape, because a carriage return cannot be represented", my lineIndex, theIndex)
			else if theCode = 39 then
				raise("A ' needs no escape inside \"...\"", my lineIndex, theIndex)
			else if theCode = 10 or theCode = -1 then
				raise("A backslash must be followed by an escape character. Use \\\\ for a literal backslash, or a '...' string", my lineIndex, theIndex)
			end if
			raise("Unknown escape “\\" & textFromCodes({theCode}) & "”. The escapes are \\\\, \\\", \\n, \\t, and \\u{…}; use a '...' string for literal backslashes", my lineIndex, theIndex)
		end readEscape

		on readUnicodeEscape(theIndex)
			-- `\u{` then one to six hexadecimal digits of either case, for the messages, then `}`.
			set digitStart to theIndex + 3
			set digitEnd to digitStart
			set codePoint to 0
			set hasUppercase to false
			if item (theIndex + 2) of my sourceCodes = 123 then
				repeat while digitEnd - digitStart < 7
					set theCode to item digitEnd of my sourceCodes
					if theCode ≥ 48 and theCode ≤ 57 then
						set codePoint to codePoint * 16 + theCode - 48
					else if theCode ≥ 97 and theCode ≤ 102 then
						set codePoint to codePoint * 16 + theCode - 87
					else if theCode ≥ 65 and theCode ≤ 70 then
						set codePoint to codePoint * 16 + theCode - 55
						set hasUppercase to true
					else
						exit repeat
					end if
					set digitEnd to digitEnd + 1
				end repeat
			end if
			set digitCount to digitEnd - digitStart
			if item (theIndex + 2) of my sourceCodes is not 123 or digitCount = 0 or digitCount > 6 or item digitEnd of my sourceCodes is not 125 then
				raise(describeBadUnicodeEscape(theIndex), my lineIndex, theIndex)
			end if
			if codePoint = 13 then
				raise("A carriage return (U+000D) cannot be represented, so \\u{" & sliceText(digitStart, digitEnd - 1) & "} is not allowed", my lineIndex, theIndex)
			end if
			if codePoint ≥ 55296 and codePoint ≤ 57343 then
				raise("\\u{" & sliceText(digitStart, digitEnd - 1) & "} is a surrogate, which is not a Unicode scalar value", my lineIndex, theIndex)
			end if
			if codePoint > 1114111 then
				raise("\\u{" & sliceText(digitStart, digitEnd - 1) & "} is above U+10FFFF, the largest Unicode scalar value", my lineIndex, theIndex)
			end if
			if hasUppercase then
				raise("A Unicode escape uses lowercase hexadecimal digits", my lineIndex, theIndex)
			end if
			if digitCount > 1 and item digitStart of my sourceCodes = 48 then
				raise("A Unicode escape may not have leading zeros; write \\u{" & lowercaseHex(codePoint) & "}", my lineIndex, theIndex)
			end if
			return {codePoint, digitEnd + 1}
		end readUnicodeEscape

		on describeBadUnicodeEscape(theIndex)
			set startIndex to theIndex + 1
			-- The JSON form \uXXXX.
			set isFourDigit to true
			repeat with step from 1 to 4
				set theCode to item (startIndex + step) of my sourceCodes
				if not ((theCode ≥ 48 and theCode ≤ 57) or (theCode ≥ 97 and theCode ≤ 102) or (theCode ≥ 65 and theCode ≤ 70)) then
					set isFourDigit to false
					exit repeat
				end if
			end repeat
			if isFourDigit then
				set hexDigits to sliceText(startIndex + 1, startIndex + 4)
				set theCode to hexValue(startIndex + 1, startIndex + 4)
				set form to "The four-digit \\u" & hexDigits & " form is not an escape"
				if theCode ≥ 55296 and theCode ≤ 56319 and item (startIndex + 5) of my sourceCodes = 92 and item (startIndex + 6) of my sourceCodes = 117 then
					set isLow to true
					repeat with step from 7 to 10
						set lowCode to item (startIndex + step) of my sourceCodes
						if not ((lowCode ≥ 48 and lowCode ≤ 57) or (lowCode ≥ 97 and lowCode ≤ 102) or (lowCode ≥ 65 and lowCode ≤ 70)) then
							set isLow to false
							exit repeat
						end if
					end repeat
					if isLow then
						set lowValue to hexValue(startIndex + 7, startIndex + 10)
						if lowValue ≥ 56320 and lowValue ≤ 57343 then
							set codePoint to 65536 + (theCode - 55296) * 1024 + (lowValue - 56320)
							return "The four-digit \\u" & hexDigits & "\\u" & sliceText(startIndex + 7, startIndex + 10) & " form is not an escape. Write \\u{" & lowercaseHex(codePoint) & "}"
						end if
					end if
				end if
				if theCode ≥ 55296 and theCode ≤ 57343 then
					return form & ", and a lone surrogate is not a Unicode scalar value. Write the character it is half of as one \\u{…} escape"
				end if
				if theCode = 13 then
					return form & ", and a carriage return (U+000D) cannot be represented"
				end if
				return form & ". Write \\u{" & lowercaseHex(theCode) & "}"
			end if
			if item (startIndex + 1) of my sourceCodes = 123 then
				set theIndex to startIndex + 2
				set digitCount to 0
				set hasUppercase to false
				repeat
					set theCode to item theIndex of my sourceCodes
					if (theCode ≥ 48 and theCode ≤ 57) or (theCode ≥ 97 and theCode ≤ 102) then
						set digitCount to digitCount + 1
					else if theCode ≥ 65 and theCode ≤ 70 then
						set digitCount to digitCount + 1
						set hasUppercase to true
					else
						exit repeat
					end if
					set theIndex to theIndex + 1
				end repeat
				if hasUppercase then
					return "A Unicode escape uses lowercase hexadecimal digits"
				end if
				if digitCount = 0 and item theIndex of my sourceCodes = 125 then
					return "A Unicode escape needs one to six hexadecimal digits"
				end if
				if digitCount ≥ 7 then
					return "A Unicode escape has at most six hexadecimal digits"
				end if
			end if
			return "A Unicode escape is written \\u{…} with one to six lowercase hexadecimal digits"
		end describeBadUnicodeEscape

		on hexValue(firstIndex, lastIndex)
			set theValue to 0
			repeat with theIndex from firstIndex to lastIndex
				set theCode to item theIndex of my sourceCodes
				if theCode ≥ 97 then
					set theValue to theValue * 16 + theCode - 87
				else if theCode ≥ 65 then
					set theValue to theValue * 16 + theCode - 55
				else
					set theValue to theValue * 16 + theCode - 48
				end if
			end repeat
			return theValue
		end hexValue

		(*
		A block string opens with a run of three or more quotes and a line break, and closes at the first line that holds, after spaces and tabs, a run of exactly that many quotes. The closing line's indentation is removed from every content line except a blank one.
		*)
		on readBlockString(quoteCode)
			set startLine to my lineIndex
			set startIndex to my cursor
			set theIndex to startIndex
			repeat while item theIndex of my sourceCodes = quoteCode
				set theIndex to theIndex + 1
			end repeat
			set delimiterLength to theIndex - startIndex
			set my cursor to theIndex
			set theCode to item theIndex of my sourceCodes
			if theCode = -1 then
				raise("Unterminated block string", startLine, startIndex)
			end if
			if theCode is not 10 then
				fail("A block string's opening delimiter must be followed directly by a line break, and its content starts on the next line")
			end if
			crossLineBreak()
			-- Each content line: {codes, first index, last index, line, is blank}.
			set my blockLines to {}
			repeat
				set lineStart to my cursor
				set theIndex to skipHorizontalSpace(lineStart)
				if item theIndex of my sourceCodes = quoteCode then
					set runEnd to theIndex
					repeat while item runEnd of my sourceCodes = quoteCode
						set runEnd to runEnd + 1
					end repeat
					if runEnd - theIndex = delimiterLength then
						set indentation to {}
						if theIndex > lineStart then
							set indentation to items lineStart thru (theIndex - 1) of my sourceCodes
						end if
						set my cursor to runEnd
						exit repeat
					end if
				end if
				set isBlank to item theIndex of my sourceCodes is in {10, -1}
				if not my hasInnerLineBreak then
					set theIndex to count my sourceCodes
				else
					repeat while item theIndex of my sourceCodes is not in {10, -1}
						set theIndex to theIndex + 1
					end repeat
				end if
				set theCode to item theIndex of my sourceCodes
				set end of my blockLines to {my sourceCodes, lineStart, theIndex - 1, my lineIndex, isBlank}
				if theCode = -1 then
					raise("Unterminated block string" & describeInlineClosingDelimiter(quoteCode, delimiterLength), startLine, startIndex)
				end if
				set my cursor to theIndex
				crossLineBreak()
			end repeat
			-- The blank lines at the start and end are not content.
			set firstIndex to 1
			set lastIndex to count my blockLines
			repeat while firstIndex ≤ lastIndex and isBlankLine(firstIndex)
				set firstIndex to firstIndex + 1
			end repeat
			repeat while lastIndex ≥ firstIndex and isBlankLine(lastIndex)
				set lastIndex to lastIndex - 1
			end repeat
			set indentationLength to count indentation
			repeat with theIndex from firstIndex to lastIndex
				if not isBlankLine(theIndex) then
					set lineFirst to item 2 of item theIndex of my blockLines
					set lineLast to item 3 of item theIndex of my blockLines
					set lineNumber to item 4 of item theIndex of my blockLines
					set matches to lineLast - lineFirst + 1 ≥ indentationLength
					if matches and indentationLength > 0 then
						set matches to (items lineFirst thru (lineFirst + indentationLength - 1) of item 1 of item theIndex of my blockLines) = indentation
					end if
					if not matches then
						raise("This line does not start with the indentation of its block string's closing delimiter. Every line except a blank one must start with exactly the same spaces and tabs", lineNumber, lineFirst)
					end if
				end if
			end repeat
			script Store
				property texts : {}
			end script
			repeat with theIndex from firstIndex to lastIndex
				if isBlankLine(theIndex) then
					set end of Store's texts to ""
				else
					set lineFirst to item 2 of item theIndex of my blockLines
					set lineLast to item 3 of item theIndex of my blockLines
					set lineNumber to item 4 of item theIndex of my blockLines
					set contentFirst to lineFirst + indentationLength
					if contentFirst > lineLast then
						set end of Store's texts to ""
					else if quoteCode = 39 then
						set end of Store's texts to string id (items contentFirst thru lineLast of item 1 of item theIndex of my blockLines)
					else
						set my lineSource to item 1 of item theIndex of my blockLines
						set end of Store's texts to unescapeLine(contentFirst, lineLast, lineNumber)
					end if
				end if
			end repeat
			set my blockLines to {}
			return joinTexts(Store's texts, linefeed)
		end readBlockString

		on isBlankLine(blockIndex)
			return item 5 of item blockIndex of my blockLines
		end isBlankLine

		-- The hint for a content line that ends with the delimiter, as TOML allows.
		on describeInlineClosingDelimiter(quoteCode, delimiterLength)
			repeat with lineIndexInBlock from 1 to count my blockLines
				set my lineSource to item 1 of item lineIndexInBlock of my blockLines
				set lineFirst to item 2 of item lineIndexInBlock of my blockLines
				set lineLast to item 3 of item lineIndexInBlock of my blockLines
				set lineNumber to item 4 of item lineIndexInBlock of my blockLines
				set lastIndex to lineLast
				repeat while lastIndex ≥ lineFirst and (isHorizontalSpaceCode(item lastIndex of my lineSource))
					set lastIndex to lastIndex - 1
				end repeat
				set firstIndex to lineFirst
				repeat while firstIndex ≤ lastIndex and (isHorizontalSpaceCode(item firstIndex of my lineSource))
					set firstIndex to firstIndex + 1
				end repeat
				set runStart to lastIndex + 1
				repeat while runStart > firstIndex and item (runStart - 1) of my lineSource = quoteCode
					set runStart to runStart - 1
				end repeat
				if lastIndex - runStart + 1 ≥ delimiterLength and runStart > firstIndex then
					set delimiter to string id (items runStart thru (runStart + delimiterLength - 1) of my lineSource)
					return ". Its closing delimiter must start a line, so move the " & delimiter & " at the end of line " & (item 1 of locate(lineNumber, lineFirst)) & " to a new line"
				end if
			end repeat
			return ""
		end describeInlineClosingDelimiter

		-- Decodes the escapes of one content line of a """ block, and returns its text.
		on unescapeLine(firstIndex, lastIndex, lineNumber)
			set savedSource to my sourceCodes
			set savedLine to my lineIndex
			set my sourceCodes to my lineSource
			set my lineIndex to lineNumber
			script Store
				property parts : {}
			end script
			set chunkStart to firstIndex
			set theIndex to firstIndex
			repeat while theIndex ≤ lastIndex
				if item theIndex of my sourceCodes = 92 then
					if theIndex > chunkStart then
						set end of Store's parts to string id (items chunkStart thru (theIndex - 1) of my sourceCodes)
					end if
					set {escapedCode, theIndex} to readEscape(theIndex)
					set end of Store's parts to textFromCodes({escapedCode})
					set chunkStart to theIndex
				else
					set theIndex to theIndex + 1
				end if
			end repeat
			if chunkStart ≤ lastIndex then
				set end of Store's parts to string id (items chunkStart thru lastIndex of my sourceCodes)
			end if
			set my sourceCodes to savedSource
			set my lineIndex to savedLine
			return joinTexts(Store's parts, "")
		end unescapeLine

		-- Numbers, dates, instants, and durations

		(*
		Reads the run of letters, digits, and `_ . : + -` that starts at `cursor`, which is an int, a float, a date, an instant, or a duration.
		*)
		on readNumberToken()
			set startIndex to my cursor
			set theIndex to numberTokenEnd(startIndex + 1)
			set my cursor to theIndex
			set tokenCodes to items startIndex thru (theIndex - 1) of my sourceCodes
			return parseNumberCodes(tokenCodes, my lineIndex, startIndex)
		end readNumberToken

		-- The first index outside a run of numeric-token characters.
		on numberTokenEnd(theIndex)
			repeat
				set theCode to item theIndex of my sourceCodes
				if isNumberTokenCode(theCode) then
					set theIndex to theIndex + 1
				else
					exit repeat
				end if
			end repeat
			return theIndex
		end numberTokenEnd

		on parseNumberCodes(tokenCodes, atLine, atPosition)
			set theCount to count tokenCodes
			-- A whole date token preserves its components; a longer date prefix gets instant diagnostics, and a date is on its own only when no time, with an hour of one or two digits, follows the spaces or tabs after it, so `2026-09-19  14:00` still gets the separator diagnostic.
			if theCount ≥ 10 and item 5 of tokenCodes = 45 and item 8 of tokenCodes = 45 and my isDigitRun(tokenCodes, {1, 2, 3, 4, 6, 7, 9, 10}) then
				if theCount = 10 then
					set theIndex to skipHorizontalSpace(my cursor)
					set isValid to not isDigitCode(item theIndex of my sourceCodes)
					if not isValid then
						if item (theIndex + 1) of my sourceCodes = 58 then
							set isValid to not (theIndex + 3 ≤ (count my sourceCodes) and isDigitCode(item (theIndex + 2) of my sourceCodes) and isDigitCode(item (theIndex + 3) of my sourceCodes))
						else
							set isValid to not (theIndex + 4 ≤ (count my sourceCodes) and isDigitCode(item (theIndex + 1) of my sourceCodes) and item (theIndex + 2) of my sourceCodes = 58 and isDigitCode(item (theIndex + 3) of my sourceCodes) and isDigitCode(item (theIndex + 4) of my sourceCodes))
						end if
					end if
					if isValid then
						return {class:«class SOMc», value:parseDateCodes(tokenCodes, atLine, atPosition)}
					end if
					diagnoseSpaceSeparatedInstant(tokenCodes, atLine, atPosition)
				end if
				-- More of the instant may follow the token, and a whole value is described differently from one that other text follows. A value ends where a suggestion that is offered alone ends, so a slash only counts when it starts a comment, and a comma before a digit starts a range of instants rather than a next item. A number that follows the spaces moves the end, as in `2026-09-19T14:00:00 5,`.
				set endCode to item (my cursor) of my sourceCodes
				set nextIndex to my cursor
				if endCode is in {32, 9} then
					set theIndex to skipHorizontalSpace(my cursor)
					if isDigitCode(item theIndex of my sourceCodes) then
						set nextIndex to numberTokenEnd(theIndex + 1)
						set endCode to item nextIndex of my sourceCodes
					end if
				end if
				set isWholeValue to isValueEndCode(endCode) and (endCode is not 47 or item (nextIndex + 1) of my sourceCodes is in {42, 47})
				if endCode = 44 and isDigitCode(item (nextIndex + 1) of my sourceCodes) then
					set isWholeValue to false
				end if
				return {class:«class SOMt», value:parseInstantCodes(tokenCodes, atLine, atPosition, isWholeValue)}
			end if
			set numberKind to classifyNumber(tokenCodes)
			if numberKind = "int" then
				if tokenCodes = {45, 48} then
					raise("“-0” is not allowed, because zero has one spelling: 0", atLine, atPosition)
				end if
				return intValue(tokenCodes, atLine, atPosition)
			end if
			if numberKind = "float" then
				set tokenText to string id tokenCodes
				if tokenCodes does not contain 95 then
					return deferFloat(tokenText, tokenText, atLine, atPosition)
				end if
				set normalizedText to ((current application's NSString's stringWithString:tokenText)'s stringByReplacingOccurrencesOfString:"_" withString:"") as text
				return deferFloat(normalizedText, tokenText, atLine, atPosition)
			end if
			if isDurationLike(tokenCodes) then
				set {theSeconds, theNanoseconds, isNegative} to durationPartsAt(tokenCodes, atLine, atPosition)
				return {class:«class SOMd», value:formatDuration(theSeconds, theNanoseconds, isNegative)}
			end if
			raise(describeBadNumber(tokenCodes, atLine, atPosition), atLine, atPosition)
		end parseNumberCodes

		(*
		Converts the floats read so far, in one batch, and puts them in their places.
		*)
		on convertFloats()
			if my pendingFloats is {} then
				return
			end if
			script Store
				property pending : my pendingFloats
				property texts : {}
				property results : {}
			end script
			set my pendingFloats to {}
			repeat with step from 1 to count Store's pending
				set end of Store's texts to item 3 of item step of Store's pending
			end repeat
			set Store's results to callJavaScript(floatJavaScriptContext(), "somlParseFloats", my floatScript, Store's texts)
			repeat with step from 1 to count Store's pending
				set theResult to item step of Store's results
				if class of theResult is text then
					set tokenText to item 6 of item step of Store's pending
					set atLine to item 4 of item step of Store's pending
					set atPosition to item 5 of item step of Store's pending
					if theResult = "infinite" then
						if (id of character 1 of tokenText) = 45 then
							raise(abbreviate(tokenText, 40) & " is too large to be a finite float. Use -infinity if you mean it", atLine, atPosition)
						end if
						raise(abbreviate(tokenText, 40) & " is too large to be a finite float. Use infinity if you mean it", atLine, atPosition)
					end if
					raise(abbreviate(tokenText, 40) & " is too small to be told apart from zero. Write 0.0 if you mean zero", atLine, atPosition)
				end if
				-- A syntax or duplicate-key error can precede inserting this float into its collection.
				if item 2 of item step of Store's pending ≤ (count item 1 of item step of Store's pending) then
					set item (item 2 of item step of Store's pending) of item 1 of item step of Store's pending to theResult as real
				end if
			end repeat
		end convertFloats

		(*
		Whether the codes are an int, in any radix, or a float, following the grammar: "int", "float", or "".
		*)
		on classifyNumber(theCodes)
			script Store
				property codes : theCodes
			end script
			set theCount to count Store's codes
			if theCount ≥ 2 and item 1 of Store's codes = 48 and item 2 of Store's codes is in {120, 111, 98} then
				set digitEnd to skipDigits(theCodes, 3, item 2 of Store's codes)
				if digitEnd > 3 and digitEnd = theCount + 1 then
					return "int"
				end if
				return ""
			end if
			set theIndex to 1
			if item 1 of Store's codes = 45 then
				set theIndex to 2
			end if
			set integerEnd to skipIntegerPart(theCodes, theIndex)
			if integerEnd = theIndex then
				return ""
			end if
			set theIndex to integerEnd
			set numberKind to "int"
			if theIndex ≤ theCount and item theIndex of Store's codes = 46 then
				set digitEnd to skipDigits(theCodes, theIndex + 1, 100)
				if digitEnd = theIndex + 1 then
					return ""
				end if
				set theIndex to digitEnd
				set numberKind to "float"
			end if
			if theIndex ≤ theCount and item theIndex of Store's codes = 101 then
				set exponentStart to theIndex + 1
				set isNegative to exponentStart ≤ theCount and item exponentStart of Store's codes = 45
				if isNegative then
					set exponentStart to exponentStart + 1
				end if
				if isNegative and exponentStart ≤ theCount and item exponentStart of Store's codes = 48 then
					set exponentEnd to exponentStart
				else
					set exponentEnd to skipIntegerPart(theCodes, exponentStart)
				end if
				if exponentEnd = exponentStart then
					return ""
				end if
				set theIndex to exponentEnd
				set numberKind to "float"
			end if
			if theIndex = theCount + 1 then
				return numberKind
			end if
			return ""
		end classifyNumber

		(*
		The index after a run of digits that may have single underscores between them. `radix` is 120 (x), 111 (o), 98 (b), or 100 for decimal.
		*)
		on skipDigits(theCodes, theIndex, radix)
			script Store
				property codes : theCodes
			end script
			set theCount to count Store's codes
			if theIndex > theCount or not isRadixDigit(item theIndex of Store's codes, radix) then
				return theIndex
			end if
			set theIndex to theIndex + 1
			set maximumDigit to 57
			if radix = 111 then
				set maximumDigit to 55
			else if radix = 98 then
				set maximumDigit to 49
			end if
			set isHexadecimal to radix = 120
			repeat
				if theIndex > theCount then
					return theIndex
				end if
				set theCode to item theIndex of Store's codes
				if (theCode ≥ 48 and theCode ≤ maximumDigit) or (isHexadecimal and theCode ≥ 65 and theCode ≤ 70) then
					set theIndex to theIndex + 1
				else if theCode = 95 and theIndex < theCount then
					set nextCode to item (theIndex + 1) of Store's codes
					if not ((nextCode ≥ 48 and nextCode ≤ maximumDigit) or (isHexadecimal and nextCode ≥ 65 and nextCode ≤ 70)) then
						return theIndex
					end if
					set theIndex to theIndex + 2
				else
					return theIndex
				end if
			end repeat
		end skipDigits

		on isRadixDigit(theCode, radix)
			if radix = 100 then
				return theCode ≥ 48 and theCode ≤ 57
			else if radix = 120 then
				return (theCode ≥ 48 and theCode ≤ 57) or (theCode ≥ 65 and theCode ≤ 70)
			else if radix = 111 then
				return theCode ≥ 48 and theCode ≤ 55
			end if
			return theCode = 48 or theCode = 49
		end isRadixDigit

		on skipIntegerPart(theCodes, theIndex)
			script Store
				property codes : theCodes
			end script
			if theIndex ≤ (count Store's codes) and item theIndex of Store's codes = 48 then
				return theIndex + 1
			end if
			return skipDigits(theCodes, theIndex, 100)
		end skipIntegerPart

		(*
		An int as an integer, or as a tagged int outside AppleScript's range.
		*)
		on intValue(tokenCodes, atLine, atPosition)
			script Store
				property codes : tokenCodes
			end script
			set isRadix to (count Store's codes) ≥ 2 and item 1 of Store's codes = 48 and item 2 of Store's codes is in {120, 111, 98}
			set isNegative to item 1 of Store's codes = 45
			set digits to {}
			if isRadix then
				set radixCode to item 2 of Store's codes
				if radixCode = 120 then
					set radix to 16
					set maximumDigits to 16
				else if radixCode = 111 then
					set radix to 8
					set maximumDigits to 22
				else
					set radix to 2
					set maximumDigits to 64
				end if
				repeat with theIndex from 3 to count Store's codes
					set theCode to item theIndex of Store's codes
					if theCode is not 95 and not (digits = {} and theCode = 48) then
						set end of digits to theCode
						if (count digits) > maximumDigits then
							failIntRange(tokenCodes, atLine, atPosition)
						end if
					end if
				end repeat

				set decimalDigits to radixToDecimal(digits, radix)
			else
				set firstIndex to 1
				if isNegative then
					set firstIndex to 2
				end if
				repeat with theIndex from firstIndex to count Store's codes
					set theCode to item theIndex of Store's codes
					if theCode is not 95 then
						set end of digits to theCode
						if (count digits) > 19 then
							failIntRange(tokenCodes, atLine, atPosition)
						end if
					end if
				end repeat
				set decimalDigits to digits
			end if
			set digitCount to count decimalDigits
			if digitCount ≤ 9 then
				set theValue to 0
				repeat with theCode in decimalDigits
					set theValue to theValue * 10 + (theCode - 48)
				end repeat
				if isNegative then
					set theValue to -theValue
				end if
				if theValue ≥ smallestInteger and theValue ≤ largestInteger then
					return theValue as integer
				end if
			else if digitCount > 19 then
				failIntRange(tokenCodes, atLine, atPosition)
			else if digitCount = 19 then
				if isNegative then
					set limit to {57, 50, 50, 51, 51, 55, 50, 48, 51, 54, 56, 53, 52, 55, 55, 53, 56, 48, 56}
				else
					set limit to {57, 50, 50, 51, 51, 55, 50, 48, 51, 54, 56, 53, 52, 55, 55, 53, 56, 48, 55}
				end if
				if compareCodes(decimalDigits, limit) > 0 then
					failIntRange(tokenCodes, atLine, atPosition)
				end if
			end if
			if isNegative then
				return {class:«class SOMi», value:"-" & string id decimalDigits}
			end if
			return {class:«class SOMi», value:string id decimalDigits}
		end intValue

		on failIntRange(tokenCodes, atLine, atPosition)
			raise("The integer " & abbreviateCodes(tokenCodes, 40) & " is outside the 64-bit range (-9223372036854775808 to 9223372036854775807)", atLine, atPosition)
		end failIntRange

		-- Digits in a radix as decimal digits, with limbs of seven decimal digits, which stay exact in reals.
		on radixToDecimal(digits, radix)
			set limbs to {0}
			repeat with theCode in digits
				set theCode to contents of theCode
				if theCode ≥ 65 then
					set digitValue to theCode - 55
				else
					set digitValue to theCode - 48
				end if
				set carry to digitValue
				repeat with theIndex from (count limbs) to 1 by -1
					set product to (item theIndex of limbs) * radix + carry
					set item theIndex of limbs to product mod 10000000
					set carry to product div 10000000
				end repeat
				if carry > 0 then
					set beginning of limbs to carry
				end if
			end repeat
			set decimalText to ((item 1 of limbs) as integer) as text
			repeat with theIndex from 2 to count limbs
				set decimalText to decimalText & padNumber(item theIndex of limbs, 7)
			end repeat
			return codePoints(decimalText)
		end radixToDecimal

		-- Tagged values, which accept any spelling that SOML does.

		-- The value of a tagged int in any SOML spelling: an integer, or a tagged int in decimal. Errors with number 1 when it is not an int.
		on parseTaggedInt(theText)
			set theCodes to codePoints(theText)
			if theCodes = {} or classifyNumber(theCodes) is not "int" or theCodes = {45, 48} then
				error "“" & abbreviate(theText, 40) & "” is not a SOML int" number my invalidDocumentErrorNumber
			end if
			return intValue(theCodes, 1, 1)
		end parseTaggedInt

		-- A calendar date's exact components, without an instant or timezone conversion. The exact ASCII token shape is checked before arithmetic.
		on parseDateCodes(theCodes, atLine, atPosition)
			if (count theCodes) is not 10 or item 5 of theCodes is not 45 or item 8 of theCodes is not 45 or not isDigitRun(theCodes, {1, 2, 3, 4, 6, 7, 9, 10}) then
				raise("“" & abbreviateCodes(theCodes, 40) & "” is not a SOML date", atLine, atPosition)
			end if
			set theYear to twoDigits(theCodes, 1) * 100 + twoDigits(theCodes, 3)
			set problem to calendarDateProblem(theYear, twoDigits(theCodes, 6), twoDigits(theCodes, 9))
			if problem is not missing value then
				raise("Invalid date " & (string id theCodes) & ": " & problem, atLine, atPosition)
			end if
			return string id theCodes
		end parseDateCodes

		-- The canonical form of a tagged instant in any SOML spelling. Errors with number 1 when it is not an instant.
		on parseTaggedInstant(theText)
			set theCodes to codePoints(theText)
			if (count theCodes) < 10 then
				error "“" & abbreviate(theText, 40) & "” is not a SOML instant" number my invalidDocumentErrorNumber
			end if
			return parseInstantCodes(theCodes, 1, 1, true)
		end parseTaggedInstant

		-- The whole seconds since 1970 of a tagged instant, without its fraction.
		on instantEpochSeconds(theText)
			set theCodes to codePoints(parseTaggedInstant(theText))
			set theDays to daysFromCivil((twoDigits(theCodes, 1)) * 100 + (twoDigits(theCodes, 3)), twoDigits(theCodes, 6), twoDigits(theCodes, 9))
			return (theDays as real) * 86400 + (twoDigits(theCodes, 12)) * 3600 + (twoDigits(theCodes, 15)) * 60 + (twoDigits(theCodes, 18))
		end instantEpochSeconds

		(*
		Validates an instant and returns its canonical form, in UTC.
		*)
		on parseInstantCodes(theCodes, atLine, atPosition, isWholeValue)
			script Store
				property codes : theCodes
			end script
			set canonicalText to canonicalUTCInstant(theCodes)
			if canonicalText is not missing value then
				return canonicalText
			end if
			set theCount to count Store's codes
			-- A longer token gets only the general message, even when a specific reason, such as the fraction limit, would apply.
			if theCount > 1000 then
				raise(describeBadInstant(theCodes, string id theCodes, isWholeValue), atLine, atPosition)
			end if
			set isValid to theCount ≥ 20 and item 5 of Store's codes = 45 and item 8 of Store's codes = 45 and item 11 of Store's codes = 84 and item 14 of Store's codes = 58 and item 17 of Store's codes = 58 and isDigitRun(theCodes, {1, 2, 3, 4, 6, 7, 9, 10, 12, 13, 15, 16, 18, 19})
			set fractionCodes to {}
			set theIndex to 20
			if isValid and item theIndex of Store's codes = 46 then
				set theIndex to theIndex + 1
				repeat while theIndex ≤ theCount and isDigitCode(item theIndex of Store's codes)
					-- Ten digits are enough to report the limit; keep scanning to preserve syntax-error priority.
					if (count fractionCodes) < 10 then
						set end of fractionCodes to item theIndex of Store's codes
					end if
					set theIndex to theIndex + 1
				end repeat
				if fractionCodes = {} then
					set isValid to false
				end if
			end if
			set offsetMinutes to 0
			set isNegativeZeroOffset to false
			if isValid then
				if theIndex = theCount and item theIndex of Store's codes = 90 then
					set offsetHour to 0
					set offsetMinute to 0
				else if theIndex + 5 = theCount and item theIndex of Store's codes is in {43, 45} and isDigitCode(item (theIndex + 1) of Store's codes) and isDigitCode(item (theIndex + 2) of Store's codes) and item (theIndex + 3) of Store's codes = 58 and isDigitCode(item (theIndex + 4) of Store's codes) and isDigitCode(item (theIndex + 5) of Store's codes) then
					set offsetHour to twoDigits(theCodes, theIndex + 1)
					set offsetMinute to twoDigits(theCodes, theIndex + 4)
					set offsetMinutes to offsetHour * 60 + offsetMinute
					if item theIndex of Store's codes = 45 then
						set offsetMinutes to -offsetMinutes
						set isNegativeZeroOffset to offsetHour = 0 and offsetMinute = 0
					end if
				else
					set isValid to false
				end if
			end if
			if not isValid then
				raise(describeBadInstant(theCodes, string id theCodes, isWholeValue), atLine, atPosition)
			end if
			if (count fractionCodes) > 9 then
				failInstant(theCodes, "a fractional second has at most nine digits", atLine, atPosition)
			end if
			set theYear to twoDigits(theCodes, 1) * 100 + twoDigits(theCodes, 3)
			set theMonth to twoDigits(theCodes, 6)
			set theDay to twoDigits(theCodes, 9)
			set theHour to twoDigits(theCodes, 12)
			set theMinute to twoDigits(theCodes, 15)
			set theSecond to twoDigits(theCodes, 18)
			set calendarProblem to calendarDateProblem(theYear, theMonth, theDay)
			if calendarProblem is not missing value then
				failInstant(theCodes, calendarProblem, atLine, atPosition)
			end if
			if theHour > 23 then
				failInstant(theCodes, "the hour must be 00 to 23", atLine, atPosition)
			end if
			if theMinute > 59 then
				failInstant(theCodes, "the minute must be 00 to 59", atLine, atPosition)
			end if
			if theSecond > 59 then
				failInstant(theCodes, "the second must be 00 to 59, and a leap second is not representable", atLine, atPosition)
			end if
			if offsetHour > 23 then
				failInstant(theCodes, "the offset hour must be 00 to 23", atLine, atPosition)
			end if
			if offsetMinute > 59 then
				failInstant(theCodes, "the offset minute must be 00 to 59", atLine, atPosition)
			end if
			if isNegativeZeroOffset then
				failInstant(theCodes, "-00:00 means “offset unknown” in RFC 3339, which is not representable; use Z or +00:00", atLine, atPosition)
			end if
			-- An instant in UTC is already in canonical form, except for zeros at the end of its fraction, and every valid date and time in UTC is in range.
			if item theCount of Store's codes = 90 then
				set fractionCodes to trimTrailingZeros(fractionCodes)
				if fractionCodes = {} then
					return (string id (items 1 thru 19 of Store's codes)) & "Z"
				end if
				return (string id (items 1 thru 19 of Store's codes)) & "." & (string id fractionCodes) & "Z"
			end if
			set epochSeconds to (daysFromCivil(theYear, theMonth, theDay) as real) * 86400 + theHour * 3600 + theMinute * 60 + theSecond - offsetMinutes * 60
			-- 0001-01-01T00:00:00Z and 9999-12-31T23:59:59Z.
			if epochSeconds < -6.21355968E+10 or epochSeconds > 2.53402300799E+11 then
				failInstant(theCodes, "in UTC it falls outside the years 0001 to 9999", atLine, atPosition)
			end if
			return formatInstant(epochSeconds, fractionCodes)
		end parseInstantCodes

		-- Creates the preview only for an invalid instant, rather than every offset instant.
		on failInstant(theCodes, reason, atLine, atPosition)
			raise("Invalid instant " & abbreviateCodes(theCodes, 40) & ": " & reason, atLine, atPosition)
		end failInstant

		(*
		A date and a time with a space between them, as TOML and Python write a date and time, where an instant has a "T". Following the example must not turn a local time into UTC silently, so a time without an offset is described as what it is.
		*)
		on diagnoseSpaceSeparatedInstant(dateCodes, atLine, atPosition)
			-- The caller enters only when a time, with an hour of one or two digits, follows the spaces after the date, so the diagnostic always raises.
			set timeStart to skipHorizontalSpace(my cursor)
			set timeEnd to numberTokenEnd(timeStart + 1)
			set timeCodes to items timeStart thru (timeEnd - 1) of my sourceCodes
			set endCode to item timeEnd of my sourceCodes
			set isWholeValue to isValueEndCode(endCode) and (endCode is not 47 or item (timeEnd + 1) of my sourceCodes is in {42, 47})
			if endCode = 44 and isDigitCode(item (timeEnd + 1) of my sourceCodes) then
				set isWholeValue to false
			end if
			set separator to "The date and time separator in an instant is an uppercase “T”, not a space"
			set instantCodes to dateCodes & {84} & timeCodes
			set instantText to string id instantCodes
			if isValidInstant(instantCodes) then
				raise(separator & ", as in " & abbreviate(instantText, 40), atLine, atPosition)
			end if
			if isWholeValue and isLocalDateTime(instantCodes) and isValidInstant(instantCodes & {90}) then
				raise(separator & ", and an instant needs the offset it was meant in, as in " & abbreviate(instantText, 40) & "Z for UTC. A date and time without an offset is a local time, which is not an instant, so write it as a string, as in '" & abbreviate((string id dateCodes) & " " & (string id timeCodes), 40) & "'", atLine, atPosition)
			end if
			raise(separator & ". An instant is written as 2026-09-19T14:00:00Z, with an optional fraction of up to nine digits and an offset of Z or ±HH:MM", atLine, atPosition)
		end diagnoseSpaceSeparatedInstant

		on isValidInstant(theCodes)
			try
				parseInstantCodes(theCodes, 1, 1, true)
				return true
			on error number 1
				return false
			end try
		end isValidInstant

		-- Whether the codes are a date and a time without an offset, as in 2026-09-19T14:00:00.5.
		on isLocalDateTime(theCodes)
			script Store
				property codes : theCodes
			end script
			set theCount to count Store's codes
			if theCount < 19 or item 5 of Store's codes is not 45 or item 8 of Store's codes is not 45 or item 11 of Store's codes is not 84 or item 14 of Store's codes is not 58 or item 17 of Store's codes is not 58 or not isDigitRun(theCodes, {1, 2, 3, 4, 6, 7, 9, 10, 12, 13, 15, 16, 18, 19}) then
				return false
			end if
			if theCount = 19 then
				return true
			end if
			if theCount = 20 or item 20 of Store's codes is not 46 then
				return false
			end if
			repeat with theIndex from 21 to theCount
				if not isDigitCode(item theIndex of Store's codes) then
					return false
				end if
			end repeat
			return true
		end isLocalDateTime

		-- The number of the two digits at `theIndex`.
		on twoDigits(theCodes, theIndex)
			return ((item theIndex of theCodes) - 48) * 10 + (item (theIndex + 1) of theCodes) - 48
		end twoDigits

		on describeBadInstant(theCodes, tokenText, isWholeValue)
			script Store
				property codes : theCodes
			end script
			set instantFormat to "An instant is written as 2026-09-19T14:00:00Z, with an optional fraction of up to nine digits and an offset of Z or ±HH:MM"
			set theCount to count Store's codes
			-- The reference bounds diagnostics at 1000 characters, so a longer token gets only the general message.
			if theCount > 1000 then
				return "Invalid instant “" & abbreviate(tokenText, 40) & "”. " & instantFormat
			end if
			if theCount = 10 then
				return "A date is not an instant. " & instantFormat
			end if
			if item 11 of Store's codes = 116 then
				return "The date and time separator in an instant is an uppercase “T”"
			end if
			if item theCount of Store's codes = 122 then
				return "The UTC offset in an instant is an uppercase “Z”"
			end if
			if theCount ≥ 5 and item (theCount - 4) of Store's codes is in {43, 45} and isDigitRun(Store's codes, {theCount - 3, theCount - 2, theCount - 1, theCount}) then
				return "An instant's offset is written with a colon, as in +07:00"
			end if
			-- A date and time without an offset.
			set isLocal to isLocalDateTime(theCodes)
			if not isLocal then
				return "Invalid instant “" & abbreviate(tokenText, 40) & "”. " & instantFormat
			end if
			if isWholeValue then
				return "An instant needs an offset: Z or ±HH:MM. A date and time without an offset is a local time, which is not an instant, so write it as a string, as in '" & abbreviate(tokenText, 40) & "', or add the offset it was meant in"
			end if
			return "An instant needs an offset: Z or ±HH:MM"
		end describeBadInstant

		(*
		Whether a token that is not a number or an instant was meant as a duration: digits, maybe a fraction, then a letter that could begin a unit.
		*)
		on isDurationLike(theCodes)
			script Store
				property codes : theCodes
			end script
			set theCount to count Store's codes
			set theIndex to 1
			if item 1 of Store's codes = 45 then
				set theIndex to 2
			end if
			if theIndex > theCount or not isDigitCode(item theIndex of Store's codes) then
				return false
			end if
			repeat while theIndex ≤ theCount and (isDigitCode(item theIndex of Store's codes) or item theIndex of Store's codes = 95)
				set theIndex to theIndex + 1
			end repeat
			if theIndex ≤ theCount and item theIndex of Store's codes = 46 then
				set theIndex to theIndex + 1
				repeat while theIndex ≤ theCount and (isDigitCode(item theIndex of Store's codes) or item theIndex of Store's codes = 95)
					set theIndex to theIndex + 1
				end repeat
			end if
			if theIndex > theCount then
				return false
			end if
			set theCode to item theIndex of Store's codes
			-- d, h, m, n, s, u, w in either case, or a year unit.
			if theCode is in {100, 104, 109, 110, 115, 117, 119, 68, 72, 77, 78, 83, 85, 87} then
				return true
			end if
			if theCode = 121 or theCode = 89 then
				set unitEnd to theIndex
				repeat while unitEnd ≤ theCount and unitEnd - theIndex ≤ 5 and isLetterCode(item unitEnd of Store's codes)
					set unitEnd to unitEnd + 1
				end repeat
				-- Every recognized year unit fits in five letters.
				if unitEnd - theIndex > 5 then
					return false
				end if
				set unit to textFromCodes(foldCase(items theIndex thru (unitEnd - 1) of Store's codes))
				return unit is in {"y", "yr", "yrs", "year", "years"}
			end if
			return false
		end isDurationLike

		on durationPartsAt(theCodes, atLine, atPosition)
			try
				return durationParts(theCodes)
			on error reason number errorNumber
				if errorNumber is not invalidDocumentErrorNumber then
					error reason number errorNumber
				end if
				raise(reason, atLine, atPosition)
			end try
		end durationPartsAt

		-- The reason that a token that starts like a number is not one, for the error.
		on describeBadNumber(theCodes, atLine, atPosition)
			script Store
				property codes : theCodes
			end script
			set theCount to count Store's codes
			if theCodes contains 43 then
				return "A “+” sign is not allowed in a number, including in an exponent"
			end if
			set isNegative to item 1 of Store's codes = 45
			set prefixStart to 1
			if isNegative then
				set prefixStart to 2
			end if
			if theCount ≥ prefixStart + 1 and item prefixStart of Store's codes = 48 and item (prefixStart + 1) of Store's codes is in {66, 79, 88} then
				return "A number prefix is lowercase: 0x, 0o, or 0b"
			end if
			if theCount ≥ prefixStart + 1 and item prefixStart of Store's codes = 48 and item (prefixStart + 1) of Store's codes is in {120, 111, 98} then
				set radixCode to item (prefixStart + 1) of Store's codes
				if radixCode = 120 then
					set radixName to "hexadecimal"
					set article to "A"
				else if radixCode = 111 then
					set radixName to "octal"
					set article to "An"
				else
					set radixName to "binary"
					set article to "A"
				end if
				if isNegative then
					return article & " " & radixName & " integer cannot have a sign, because it states a bit pattern rather than a quantity"
				end if
				if theCount = prefixStart + 1 then
					return "Expected " & radixName & " digits after “0" & textFromCodes({radixCode}) & "”"
				end if
				set digits to items (prefixStart + 2) thru theCount of Store's codes
				if radixCode = 120 then
					set hasLowercase to false
					set isHexWord to true
					repeat with theCode in digits
						set theCode to contents of theCode
						if theCode ≥ 97 and theCode ≤ 102 then
							set hasLowercase to true
						else if not ((theCode ≥ 48 and theCode ≤ 57) or (theCode ≥ 65 and theCode ≤ 70) or theCode = 95) then
							set isHexWord to false
						end if
					end repeat
					if hasLowercase and isHexWord then
						set uppercase to {48, 120}
						repeat with theCode in digits
							set theCode to contents of theCode
							if theCode ≥ 97 and theCode ≤ 102 then
								set end of uppercase to theCode - 32
							else
								set end of uppercase to theCode
							end if
						end repeat
						if skipDigits(uppercase, 3, 120) is not (count uppercase) + 1 then
							return "An underscore in a number must be between two digits"
						end if
						try
							intValue(uppercase, atLine, atPosition)
							return "Hexadecimal digits are uppercase: " & abbreviate(string id uppercase, 40)
						on error number 1
							return "Hexadecimal digits are uppercase"
						end try
					end if
				end if
				repeat with theCode in digits
					set theCode to contents of theCode
					if theCode is not 95 and not isRadixDigit(theCode, radixCode) and not (radixCode = 120 and theCode ≥ 97 and theCode ≤ 102) then
						return "Invalid " & radixName & " digit “" & textFromCodes({theCode}) & "”"
					end if
				end repeat
				return "An underscore in a number must be between two digits"
			end if
			-- An uppercase exponent marker where an exponent goes.
			set eIndex to 0
			repeat with theIndex from 1 to theCount
				if item theIndex of Store's codes = 69 then
					set eIndex to theIndex
					exit repeat
				end if
			end repeat
			if eIndex > 1 then
				set isExponent to true
				repeat with theIndex from prefixStart to eIndex - 1
					set theCode to item theIndex of Store's codes
					if not (isDigitCode(theCode) or theCode = 95 or theCode = 46) then
						set isExponent to false
						exit repeat
					end if
				end repeat
				repeat with theIndex from eIndex + 1 to theCount
					set theCode to item theIndex of Store's codes
					if not (isDigitCode(theCode) or theCode = 95 or (theCode = 45 and theIndex = eIndex + 1)) then
						set isExponent to false
						exit repeat
					end if
				end repeat
				if isExponent and isDigitCode(item prefixStart of Store's codes) then
					return "An exponent marker is a lowercase “e”"
				end if
			end if
			-- A `.` that no digit follows.
			set dotIndex to 0
			repeat with theIndex from 1 to theCount
				if item theIndex of Store's codes = 46 then
					set dotIndex to theIndex
					exit repeat
				end if
			end repeat
			if dotIndex > prefixStart then
				set isDigitsBefore to true
				repeat with theIndex from prefixStart to dotIndex - 1
					if not (isDigitCode(item theIndex of Store's codes) or item theIndex of Store's codes = 95) then
						set isDigitsBefore to false
						exit repeat
					end if
				end repeat
				if isDigitsBefore and (dotIndex = theCount or not (isDigitCode(item (dotIndex + 1) of Store's codes) or item (dotIndex + 1) of Store's codes = 95)) then
					return "A decimal point must be followed by a digit"
				end if
			end if
			if isNegative and theCount ≥ 2 and item 2 of Store's codes = 46 then
				return "A number cannot begin with “.”; write a digit before it, as in -0.5"
			end if
			if theCodes contains 58 then
				set isColonNumber to true
				repeat with theCode in theCodes
					if not (isDigitCode(contents of theCode) or contents of theCode = 58) then
						set isColonNumber to false
						exit repeat
					end if
				end repeat
				if isColonNumber and item 1 of Store's codes is not 58 and item theCount of Store's codes is not 58 then
					if isTimeOfDay(theCodes) then
						return "A time of day is a string, so it must be quoted"
					end if
					return "Invalid number “" & abbreviateCodes(theCodes, 40) & "”. A value that contains “:” must be quoted, as in '" & abbreviateCodes(theCodes, 40) & "'"
				end if
			end if
			if theCount ≥ prefixStart + 1 and item prefixStart of Store's codes = 48 and (isDigitCode(item (prefixStart + 1) of Store's codes) or item (prefixStart + 1) of Store's codes = 95) and theCodes does not contain 58 then
				set fullText to unquotedText(atPosition)
				set identifier to "an identifier, such as a ZIP code, as a string"
				if fullText does not contain "'" then
					set identifier to identifier & ": '" & abbreviate(fullText, 40) & "'"
				end if
				set isAllDigits to true
				set isOctal to true
				repeat with theCode in theCodes
					set theCode to contents of theCode
					if not isDigitCode(theCode) then
						set isAllDigits to false
					end if
					if not (theCode ≥ 48 and theCode ≤ 55) then
						set isOctal to false
					end if
				end repeat
				if isOctal and codePoints(fullText) = theCodes then
					set firstDigit to 1
					repeat while firstDigit < theCount and item firstDigit of Store's codes = 48
						set firstDigit to firstDigit + 1
					end repeat
					set octalDigits to items firstDigit thru theCount of Store's codes
					set octal to {48, 111} & octalDigits
					try
						intValue(octal, atLine, atPosition)
						return "Leading zeros are not allowed in a decimal number. Write an octal number, such as a file mode, as " & abbreviate(string id octal, 40) & ", and " & identifier
					end try
				end if
				if isAllDigits then
					return "Leading zeros are not allowed in a decimal number. Write " & identifier
				end if
				return "Leading zeros are not allowed in a decimal number"
			end if
			-- A misplaced underscore, in a number with no other letters than an exponent marker.
			set isDecimalCharacters to true
			repeat with theCode in theCodes
				set theCode to contents of theCode
				if not (isDigitCode(theCode) or theCode is in {45, 46, 95, 101}) then
					set isDecimalCharacters to false
					exit repeat
				end if
			end repeat
			if isDecimalCharacters and theCodes contains 95 then
				repeat with theIndex from 1 to theCount
					if item theIndex of Store's codes = 95 then
						if theIndex = 1 or theIndex = theCount or not isDigitCode(item (theIndex - 1) of Store's codes) or not isDigitCode(item (theIndex + 1) of Store's codes) then
							return "An underscore in a number must be between two digits"
						end if
					end if
				end repeat
			end if
			set eIndex to 0
			repeat with theIndex from 1 to theCount
				if item theIndex of Store's codes = 101 then
					set eIndex to theIndex
					exit repeat
				end if
			end repeat
			if eIndex > 0 and isDecimalCharacters then
				set exponentCodes to {}
				if eIndex < theCount then
					set exponentCodes to items (eIndex + 1) thru theCount of Store's codes
				end if
				if exponentCodes = {45, 48} then
					return "“e-0” is not allowed, because an exponent of zero has one spelling: e0"
				end if
				if exponentCodes = {} or exponentCodes = {45} then
					return "Expected digits after the exponent marker “e”"
				end if
				if item 1 of exponentCodes = 45 then
					set exponentCodes to rest of exponentCodes
				end if
				if (count exponentCodes) ≥ 2 and item 1 of exponentCodes = 48 then
					return "Leading zeros are not allowed in an exponent"
				end if
			end if
			set dotCount to 0
			repeat with theCode in theCodes
				if contents of theCode = 46 then
					set dotCount to dotCount + 1
				end if
			end repeat
			if dotCount ≥ 2 then
				return "Invalid number “" & abbreviateCodes(theCodes, 40) & "”. A value with several dots, such as a version number, must be quoted"
			end if
			if isNegative and (theCount = 1 or not isDigitCode(item 2 of Store's codes)) then
				set lowercase to textFromCodes(foldCase(theCodes))
				considering case, diacriticals, hyphens, punctuation and white space
					if lowercase = "-nan" then
						return "NaN is not representable. Use null for a missing value"
					end if
					if lowercase is in {"-inf", "-infinity"} then
						return "“" & abbreviateCodes(theCodes, 40) & "” is not a value. Negative infinity is written -infinity"
					end if
				end considering
				return "Expected a digit or “infinity” after “-”"
			end if
			repeat with theCode in theCodes
				set theCode to contents of theCode
				if isLetterCode(theCode) then
					return "Invalid number “" & abbreviateCodes(theCodes, 40) & "”. A string value must be quoted" & quotingExample(unquotedText(atPosition))
				end if
			end repeat
			return "Invalid number “" & abbreviateCodes(theCodes, 40) & "”"
		end describeBadNumber

		on isTimeOfDay(theCodes)
			script Store
				property codes : theCodes
			end script
			set theCount to count Store's codes
			if theCount < 4 then
				return false
			end if
			if item 2 of Store's codes = 58 then
				set colonIndex to 2
			else if item 3 of Store's codes = 58 then
				set colonIndex to 3
			else
				return false
			end if
			if theCount = colonIndex + 2 then
				return true
			end if
			return theCount = colonIndex + 5 and item (colonIndex + 3) of Store's codes = 58
		end isTimeOfDay
	end script
	return Reader
end makeReader

(*
The magnitude of a duration as {whole seconds, nanoseconds, isNegative}, from its text or code points. Errors have number 1 and a reason without a position.
*)
on durationParts(theDuration)
	if class of theDuration is text then
		set theCodes to codePoints(theDuration)
	else
		set theCodes to theDuration
	end if
	script Store
		property source : theCodes
	end script
	set theCount to count Store's source
	set isNegative to theCount > 0 and item 1 of Store's source = 45
	set theIndex to 1
	if isNegative then
		set theIndex to 2
	end if
	if theIndex > theCount then
		my failDuration(theCodes, "expected a number at “”")
	end if
	set previousRank to 0
	set totalSeconds to 0.0
	set totalNanoseconds to 0
	set isOutOfRange to false
	repeat while theIndex ≤ theCount
		-- The integer part: `0`, or digits without a leading zero, with single underscores between digits.
		set digitStart to theIndex
		set digits to {}
		set digitCount to 0
		set theCode to item theIndex of Store's source
		if theCode = 48 then
			set end of digits to 48
			set digitCount to 1
			set theIndex to theIndex + 1
		else if theCode ≥ 49 and theCode ≤ 57 then
			repeat while theIndex ≤ theCount
				set theCode to item theIndex of Store's source
				if theCode ≥ 48 and theCode ≤ 57 then
					set digitCount to digitCount + 1
					-- No unit needs more than 21 whole digits before it is certainly out of range.
					if digitCount ≤ 21 then
						set end of digits to theCode
					end if
					set theIndex to theIndex + 1
				else if theCode = 95 and theIndex < theCount and isDigitCode(item (theIndex + 1) of Store's source) then
					set theIndex to theIndex + 1
				else
					exit repeat
				end if
			end repeat
		end if
		if digits = {} then
			if theCode = 45 and theIndex < theCount and isDigitCode(item (theIndex + 1) of Store's source) then
				my failDuration(theCodes, "only the whole duration takes a sign, as in -1h30m")
			end if
			if theCode = 43 then
				my failDuration(theCodes, "a “+” sign is not allowed")
			end if
			-- Eleven scalars are enough to detect truncation at ten UTF-16 units, without reconstructing the remainder.
			set previewEnd to theIndex + 10
			if previewEnd > theCount then
				set previewEnd to theCount
			end if
			my failDuration(theCodes, "expected a number at “" & abbreviateCodes(items theIndex thru previewEnd of Store's source, 10) & "”")
		end if
		set nextIndex to 0
		if theIndex ≤ theCount then
			set nextIndex to item theIndex of Store's source
		end if
		if item digitStart of Store's source = 48 and (nextIndex = 95 or isDigitCode(nextIndex)) then
			my failDuration(theCodes, "leading zeros are not allowed")
		end if
		if nextIndex = 95 then
			my failDuration(theCodes, "an underscore must be between two digits")
		end if
		set fractionCodes to {}
		set fractionLength to 0
		set lastNonzero to 0
		if nextIndex = 46 then
			set theIndex to theIndex + 1
			set fractionStart to theIndex
			repeat while theIndex ≤ theCount
				set theCode to item theIndex of Store's source
				if theCode ≥ 48 and theCode ≤ 57 then
					set fractionLength to fractionLength + 1
					-- Trailing zeros are unlimited, but at most 13 significant places can reach whole nanoseconds.
					if fractionLength ≤ 13 then
						set end of fractionCodes to theCode
					end if
					if theCode is not 48 then
						set lastNonzero to fractionLength
					end if
					set theIndex to theIndex + 1
				else if theCode = 95 and theIndex > fractionStart and theIndex < theCount and isDigitCode(item (theIndex + 1) of Store's source) then
					set theIndex to theIndex + 1
				else
					exit repeat
				end if
			end repeat
			if fractionLength = 0 then
				my failDuration(theCodes, "a “.” must be followed by a digit")
			end if
			if theIndex ≤ theCount and item theIndex of Store's source = 95 then
				my failDuration(theCodes, "an underscore must be between two digits")
			end if
		end if
		set unitStart to theIndex
		repeat while theIndex ≤ theCount and isLetterCode(item theIndex of Store's source)
			set theIndex to theIndex + 1
		end repeat
		if theIndex = unitStart then
			set unitCodes to {}
		else
			-- Known units need at most two letters; an invalid unit's preview needs only eleven.
			set unitPreviewEnd to theIndex - 1
			if unitPreviewEnd > unitStart + 10 then
				set unitPreviewEnd to unitStart + 10
			end if
			set unitCodes to items unitStart thru unitPreviewEnd of Store's source
		end if
		set rank to durationUnitRank(unitCodes)
		if rank = 0 then
			my failDuration(theCodes, describeBadDurationUnit(unitCodes))
		end if
		if rank ≤ previousRank then
			my failDuration(theCodes, "the units are in the order h, m, s, ms, us, ns, and each appears at most once")
		end if
		if nextIndex = 46 and theIndex ≤ theCount and isDigitCode(item theIndex of Store's source) then
			my failDuration(theCodes, "only the last part may have a fraction")
		end if
		set previousRank to rank
		-- The whole part: seconds for h, m, and s, and a split at the last 3, 6, or 9 digits for ms, us, and ns.
		if rank ≤ 3 then
			if digitCount > 12 then
				set isOutOfRange to true
			else
				set totalSeconds to totalSeconds + digitsValue(digits) * (item rank of {3600, 60, 1})
			end if
		else
			set subsecondDigits to item (rank - 3) of {3, 6, 9}
			if digitCount - subsecondDigits > 12 then
				set isOutOfRange to true
			else
				if digitCount > subsecondDigits then
					set totalSeconds to totalSeconds + digitsValue(items 1 thru (digitCount - subsecondDigits) of digits)
					set lowDigits to items (digitCount - subsecondDigits + 1) thru digitCount of digits
				else
					set lowDigits to digits
				end if
				set totalNanoseconds to totalNanoseconds + digitsValue(lowDigits) * (item (rank - 3) of {1000000, 1000, 1})
			end if
		end if
	end repeat
	if lastNonzero > 13 then
		my failDuration(theCodes, "it is not a whole number of nanoseconds")
	end if
	if lastNonzero > 0 then
		set fractionLength to lastNonzero
		set fractionCodes to items 1 thru fractionLength of fractionCodes
		-- A unit is a multiplier times a power of ten nanoseconds: 36e11, 6e10, 1e9, 1e6, 1e3, 1.
		set multiplier to item rank of {36, 6, 1, 1, 1, 1}
		set exponent to item rank of {11, 10, 9, 6, 3, 0}
		set scaled to digitsValue(fractionCodes) * multiplier
		if exponent ≥ fractionLength then
			set fractionNanoseconds to scaled * (10 ^ (exponent - fractionLength))
		else
			set divisor to 10 ^ (fractionLength - exponent)
			if scaled mod divisor is not 0 then
				my failDuration(theCodes, "it is not a whole number of nanoseconds")
			end if
			set fractionNanoseconds to scaled / divisor
		end if
		set fractionSeconds to fractionNanoseconds div 1000000000
		set totalSeconds to totalSeconds + fractionSeconds
		set totalNanoseconds to totalNanoseconds + (fractionNanoseconds mod 1000000000)
	end if
	set totalSeconds to totalSeconds + totalNanoseconds div 1000000000
	set totalNanoseconds to (totalNanoseconds mod 1000000000) as integer
	if isNegative and totalSeconds = 0 and totalNanoseconds = 0 and not isOutOfRange then
		my failDuration(theCodes, "“-” is not allowed before zero, because zero has one spelling: 0s")
	end if
	-- The int64 range of nanoseconds: 9223372036.854775807 seconds, and one more nanosecond below zero.
	set limit to 854775807
	if isNegative then
		set limit to 854775808
	end if
	if isOutOfRange or totalSeconds > 9.223372036E+9 or (totalSeconds = 9.223372036E+9 and totalNanoseconds > limit) then
		my failDuration(theCodes, "it is outside the 64-bit range of nanoseconds, about 292 years either way")
	end if
	return {totalSeconds, totalNanoseconds, isNegative}
end durationParts

-- Builds a duration diagnostic only on failure, so valid durations need no text reconstruction or preview.
on failDuration(theCodes, reason)
	error "Invalid duration " & abbreviateCodes(theCodes, 40) & ": " & reason number invalidDocumentErrorNumber
end failDuration

on digitsValue(theDigits)
	set theValue to 0.0
	repeat with theCode in theDigits
		set theValue to theValue * 10 + ((contents of theCode) - 48)
	end repeat
	return theValue
end digitsValue

-- The rank of a duration unit, from 1 for h to 6 for ns, or 0.
on durationUnitRank(unitCodes)
	if unitCodes = {104} then
		return 1
	else if unitCodes = {109} then
		return 2
	else if unitCodes = {115} then
		return 3
	else if unitCodes = {109, 115} then
		return 4
	else if unitCodes = {117, 115} then
		return 5
	else if unitCodes = {110, 115} then
		return 6
	end if
	return 0
end durationUnitRank

on describeBadDurationUnit(unitCodes)
	if unitCodes = {} then
		return "every number needs a unit: h, m, s, ms, us, or ns"
	end if
	set unit to textFromCodes(unitCodes)
	considering case, diacriticals, hyphens, punctuation and white space
		if unit is in {"d", "day", "days"} then
			return "there is no day unit, because a day is not a fixed length. Write 24h for a fixed 24 hours"
		end if
		if unit is in {"w", "week", "weeks"} then
			return "there is no week unit, because a day is not a fixed length. Write 168h for a fixed 168 hours"
		end if
	end considering
	set lowercase to textFromCodes(foldCase(unitCodes))
	considering case, diacriticals, hyphens, punctuation and white space
		if lowercase is in {"y", "yr", "yrs", "year", "years"} then
			return "there is no year unit, because a year is not a fixed length. Write 8760h for a fixed 365 days"
		end if
		if unit = "M" then
			return "there is no month unit, because a month is not a fixed length"
		end if
		if lowercase is in {"h", "m", "s", "ms", "us", "ns"} then
			return "the units are lowercase: " & lowercase
		end if
	end considering
	return "“" & abbreviate(unit, 10) & "” is not a unit. The units are h, m, s, ms, us, and ns, and a string must be quoted"
end describeBadDurationUnit

-- Writer

on encodeValue(theValue, isCanonical)
	set theClass to class of theValue
	if theClass is not record and theClass is not list and theClass is not «class SOMo» then
		error "A SOML document is an object or an array, so encode a record or a list, not " & my describeClass(theValue) & "." number my unsupportedValueErrorNumber
	end if
	set theValue to my resolveReference(theValue)
	set theWriter to my makeWriter(theValue, isCanonical)
	return theWriter's writeDocument()
end encodeValue

(*
A writer of one value. It reads the labels of every record from the value's display first, then writes the value with a stack of frames, and converts reals and dates in a batch at the end.
*)
on makeWriter(rootValue, isCanonical)
	script Writer
		property root : rootValue
		property sortsKeys : isCanonical
		-- NSMutableArray per-piece buffering was 11% to 27% slower, so retain AppleScript pieces.
		-- Output, in blocks of pieces, so that no list grows long. `blockNumber` and `pieceCount` say where the last piece is.
		property pieces : {}
		property pieceCount : 0
		property blocks : {}
		property blockNumber : 1
		-- Values converted in a batch at the end: {block number, piece number, value, parent path, parent kind, key or index}.
		property pendingReals : {}
		property pendingDates : {}
		property indentations : {""}
		property taggedReader : missing value
		-- Matches a key with a capital, for `restoreBarredLabels`. It compares the key with its lowercase form, because a pattern such as [A-Z] does not match a capital that a combining mark follows.
		property capitalPredicate : missing value
		(*
		The current collection, and the ones around it as frames: {kind, values, keys, formatted keys, display nodes, next index, level, path}, where kind 1 is an object and 2 an array. They are in properties, because AppleScript copies a list that is taken apart into variables, and an item of a list in a variable takes time in proportion to the size of the list.
		*)
		property frames : {}
		property frameDepth : 0
		property currentKind : 0
		property currentValues : {}
		property currentKeys : {}
		property currentFormattedKeys : {}
		property currentNodes : {}
		property currentIndex : 1
		property currentCount : 0
		property currentLevel : 0
		property currentPath : ""
		property currentIndentation : ""
		-- The display node of the value being opened. It is kept in a property, because getting an item of a list in a variable takes time in proportion to everything in the list, and a node holds the nodes of everything in its value.
		property nodeInHand : missing value
		-- The value being opened, and the parts of the object being opened, which are kept in properties for the same reason.
		property valueInHand : missing value
		property objectKeys : {}
		property objectValues : {}
		property objectNodes : {}
		property objectCodes : {}
		-- The collection that `openValue` opened.
		property openedKind : 0
		property openedValues : {}
		property openedKeys : {}
		property openedFormattedKeys : {}
		property openedNodes : {}
		property openedLevel : 0
		property openedPath : ""

		on fail(reason)
			error sanitize(reason) number my unsupportedValueErrorNumber
		end fail

		on emit(thePiece)
			if my pieceCount ≥ 4000 then
				set end of my blocks to my pieces
				set my pieces to {}
				set my pieceCount to 0
				set my blockNumber to (my blockNumber) + 1
			end if
			set end of my pieces to thePiece
			set my pieceCount to (my pieceCount) + 1
		end emit

		on indentation(level)
			repeat while (count my indentations) ≤ level
				set end of my indentations to (item -1 of my indentations) & tab
			end repeat
			return item (level + 1) of my indentations
		end indentation

		(*
		Writes the root value. Collections are kept on a stack of frames rather than written by recursion, because AppleScript runs out of stack at a few hundred nested handler calls.
		*)
		on writeDocument()
			readDisplayTree(my root)
			set my valueInHand to my root
			if not openValue(0, 0) then
				fail("A SOML document is an object or an array")
			end if
			if (count my openedValues) = 0 then
				return emptyCollection(my openedKind) & linefeed
			end if
			if my openedKind = 1 then
				-- The entries of the top-level object start at column 0, without braces.
				set my openedLevel to -1
			else
				emit("[" & linefeed)
			end if
			enterOpened()
			repeat
				set frameIndex to my currentIndex
				if frameIndex > my currentCount then
					set frameKind to my currentKind
					set frameLevel to my currentLevel
					set theDepth to my frameDepth
					if theDepth = 0 then
						if frameKind = 2 then
							emit("]" & linefeed)
						end if
						exit repeat
					end if
					set my currentKind to item 1 of item theDepth of my frames
					set my currentValues to item 2 of item theDepth of my frames
					set my currentKeys to item 3 of item theDepth of my frames
					set my currentFormattedKeys to item 4 of item theDepth of my frames
					set my currentNodes to item 5 of item theDepth of my frames
					set my currentIndex to item 6 of item theDepth of my frames
					set my currentLevel to item 7 of item theDepth of my frames
					set my currentPath to item 8 of item theDepth of my frames
					set my currentCount to count my currentValues
					set my currentIndentation to indentation((my currentLevel) + 1)
					set my frameDepth to theDepth - 1
					if frameKind = 1 then
						emit(indentation(frameLevel) & "}" & linefeed)
					else
						emit(indentation(frameLevel) & "]" & linefeed)
					end if
				else
					set my currentIndex to frameIndex + 1
					set itemLevel to (my currentLevel) + 1
					if my currentKind = 1 then
						set prefix to (my currentIndentation) & (item frameIndex of my currentFormattedKeys) & ": "
					else
						set prefix to my currentIndentation
					end if
					set my valueInHand to item frameIndex of my currentValues
					set theClass to class of my valueInHand
					-- A record whose `class` is a built-in class, as in {class:text}, reports that class, but it has a display node.
					if item frameIndex of my currentNodes is not missing value then
						set theClass to missing value
					end if
					-- The common scalars are written here, and everything else by `openValue`.
					if theClass is text then
						emit(prefix & formatString(my valueInHand, frameIndex) & linefeed)
					else if theClass is integer then
						emit(prefix & ((my valueInHand) as text) & linefeed)
					else if theClass is boolean then
						if my valueInHand then
							emit(prefix & "true" & linefeed)
						else
							emit(prefix & "false" & linefeed)
						end if
					else if theClass is real or theClass is date then
						emit(prefix)
						set pendingValue to {my blockNumber, my pieceCount, my valueInHand, my currentPath, my currentKind, pathItem(frameIndex)}
						if theClass is real then
							set end of my pendingReals to pendingValue
						else
							set end of my pendingDates to pendingValue
						end if
					else
						emit(prefix)
						set my nodeInHand to item frameIndex of my currentNodes
						if not openValue(itemLevel, frameIndex) then
							emit(linefeed)
						else
							if (my frameDepth) + 2 > my maximumDepth then
								fail("The value at " & childPath(frameIndex) & " is nested more than " & (my maximumDepth) & " levels deep")
							end if
							if (count my openedValues) = 0 then
								emit(emptyCollection(my openedKind) & linefeed)
							else
								if my openedKind = 1 then
									emit("{" & linefeed)
								else
									emit("[" & linefeed)
								end if
								-- The frame is stored without a variable, which would copy the lists in it.
								set my frameDepth to (my frameDepth) + 1
								if my frameDepth > (count my frames) then
									set end of my frames to {my currentKind, my currentValues, my currentKeys, my currentFormattedKeys, my currentNodes, my currentIndex, my currentLevel, my currentPath}
								else
									set item (my frameDepth) of my frames to {my currentKind, my currentValues, my currentKeys, my currentFormattedKeys, my currentNodes, my currentIndex, my currentLevel, my currentPath}
								end if
								enterOpened()
							end if
						end if
					end if
				end if
			end repeat
			return finish()
		end writeDocument

		(*
		The inline spelling of an empty collection, shared by root and nested values.
		*)
		on emptyCollection(theKind)
			if theKind = 1 then
				return "{}"
			end if
			return "[]"
		end emptyCollection

		-- The path of an item of the current collection, for error messages, such as `servers[0].port`. Item 0 is the root.
		on childPath(frameIndex)
			if frameIndex = 0 then
				return ""
			end if
			if my currentKind = 1 then
				return joinPath(my currentPath, item frameIndex of my currentKeys)
			end if
			return (my currentPath) & "[" & (frameIndex - 1) & "]"
		end childPath

		-- A path and a key, with the empty key as ''.
		on joinPath(thePath, theKey)
			if length of theKey = 0 then
				set theKey to "''"
			end if
			if length of thePath = 0 then
				return theKey
			end if
			return thePath & "." & theKey
		end joinPath

		-- The key or the index of an item of the current collection, for `describePendingPath`.
		on pathItem(frameIndex)
			if frameIndex = 0 then
				return missing value
			end if
			if my currentKind = 1 then
				return item frameIndex of my currentKeys
			end if
			return frameIndex
		end pathItem

		-- The path of a value converted at the end, from {…, parent path, parent kind, key or index}.
		on describePendingPath(pending)
			set {parentPath, parentKind, theItem} to items 4 thru 6 of pending
			if theItem is missing value then
				return "the root"
			end if
			if parentKind = 1 then
				return joinPath(parentPath, theItem)
			end if
			return parentPath & "[" & (theItem - 1) & "]"
		end describePendingPath

		on describePath(thePath)
			if length of thePath = 0 then
				return "the root"
			end if
			return thePath
		end describePath

		-- Makes the collection that `openValue` opened the current one.
		on enterOpened()
			set my currentKind to my openedKind
			set my currentValues to my openedValues
			set my currentKeys to my openedKeys
			set my currentFormattedKeys to my openedFormattedKeys
			set my currentNodes to my openedNodes
			set my currentIndex to 1
			set my currentLevel to my openedLevel
			set my currentPath to my openedPath
			set my currentCount to count my currentValues
			set my currentIndentation to indentation((my currentLevel) + 1)
		end enterOpened

		on setOpened(theKind, level, thePath)
			set my openedKind to theKind
			set my openedLevel to level
			set my openedPath to thePath
			return true
		end setOpened

		(*
		Writes `valueInHand` as a scalar and returns false, or opens it as a collection and returns true. The value is in a property, because AppleScript takes time in proportion to the size of a value for most uses of a variable that holds it.
		*)
		on openValue(level, frameIndex)
			-- A record, whatever its `class` says, has a display node that says it is one.
			if my nodeInHand is not missing value then
				if item 1 of my nodeInHand then
					return openRecord(level, frameIndex)
				end if
			end if
			set theClass to class of my valueInHand
			if theClass is list then
				if my nodeInHand is missing value or (count item 3 of my nodeInHand) is not (count my valueInHand) then
					fail("Cannot read the value at " & describePath(childPath(frameIndex)))
				end if
				set my openedValues to my valueInHand
				set my openedKeys to {}
				set my openedFormattedKeys to {}
				set my openedNodes to item 3 of my nodeInHand
				return setOpened(2, level, childPath(frameIndex))
			else if theClass is record or theClass is in {«class SOMi», «class SOMc», «class SOMt», «class SOMd», «class SOMo»} then
				return openRecord(level, frameIndex)
			else if my valueInHand is missing value or my valueInHand is null then
				emit("null")
				return false
			end if
			fail("Cannot encode " & describeClass(my valueInHand) & " at " & describePath(childPath(frameIndex)) & ". SOML holds records, lists, text, numbers, booleans, missing value, dates, and tagged values")
		end openValue

		on formatString(theText, frameIndex)
			-- The name, for an error, is only made when it is needed.
			try
				set formattedText to longFormattedString(theText)
				if formattedText is not missing value then
					return formattedText
				end if
				set theCodes to codePoints(theText)
			on error
				-- Raw data, such as «data utxt0041», reports the class text.
				fail("Cannot encode the data at " & describePath(childPath(frameIndex)) & ". Convert it to text first")
			end try
			try
				return formatStringCodes(theText, theCodes, "")
			on error message number errorNumber
				if errorNumber is my unsupportedValueErrorNumber then
					fail("Cannot encode the string at " & describePath(childPath(frameIndex)) & message)
				end if
				error message number errorNumber
			end try
		end formatString

		(*
		Opens `valueInHand` as a record: an object, a tagged object, or a tagged int, date, instant, or duration, which is written as a scalar.
		*)
		on openRecord(level, frameIndex)
			set my objectValues to (my valueInHand) as list
			set thePath to childPath(frameIndex)
			if my nodeInHand is missing value or not item 1 of my nodeInHand or (count item 2 of my nodeInHand) is not (count my objectValues) then
				fail("Cannot read the labels of the record at " & describePath(thePath))
			end if
			if item 5 of my nodeInHand is not missing value then
				fail(item 5 of my nodeInHand & " at " & describePath(thePath))
			end if
			set classIndex to item 4 of my nodeInHand
			if classIndex = 0 then
				restoreBarredLabels(my valueInHand)
				set my objectKeys to item 2 of my nodeInHand
				set my objectNodes to item 3 of my nodeInHand
				set my objectCodes to item 6 of my nodeInHand
				return openObject(level, thePath)
			end if
			set theClass to item classIndex of my objectValues
			if theClass is not in {«class SOMi», «class SOMc», «class SOMt», «class SOMd», «class SOMo»} then
				fail("Cannot encode a record of class " & className(theClass) & " at " & describePath(thePath) & ". The class of a record must be SOML int, SOML date, SOML instant, SOML duration, or SOML object, or left out")
			end if
			-- The one other label.
			set otherIndex to 1
			if classIndex = 1 then
				set otherIndex to 2
			end if
			if theClass is «class SOMo» then
				validateTaggedObject(otherIndex, thePath)
				set my nodeInHand to item otherIndex of item 3 of my nodeInHand
				set my valueInHand to item otherIndex of my objectValues
				return openTaggedObject(level, thePath)
			end if
			if (count my objectValues) is not 2 or item otherIndex of item 2 of my nodeInHand is not "value" or not isUnicodeTextValue(item otherIndex of my objectValues) then
				fail("A " & className(theClass) & " is {class:" & className(theClass) & ", value:…} with text as the value, at " & describePath(thePath))
			end if
			set theText to item otherIndex of my objectValues
			try
				if theClass is «class SOMi» then
					set theNumber to scalarReader()'s parseTaggedInt(theText)
					if class of theNumber is integer then
						emit(theNumber as text)
					else
						emit(value of theNumber)
					end if
				else if theClass is «class SOMc» then
					emit(scalarReader()'s parseDateCodes(codePoints(theText), 1, 1))
				else if theClass is «class SOMt» then
					emit(scalarReader()'s parseTaggedInstant(theText))
				else
					set {theSeconds, theNanoseconds, isNegative} to durationParts(theText)
					emit(formatDuration(theSeconds, theNanoseconds, isNegative))
				end if
			on error reason number errorNumber
				if errorNumber is not my invalidDocumentErrorNumber then
					error reason number errorNumber
				end if
				fail("Invalid " & className(theClass) & " at " & describePath(thePath) & ": " & reason)
			end try
			return false
		end openRecord

		-- Checks the shared shape of a tagged object before encoding or exposing its entries.
		on validateTaggedObject(otherIndex, thePath)
			if (count my objectValues) is not 2 or item otherIndex of item 2 of my nodeInHand is not "entries" or not isListValue(item otherIndex of my objectValues) then
				fail("A SOML object is {class:SOML object, entries:{{key, value}, …}}, at " & describePath(thePath))
			end if
		end validateTaggedObject

		(*
		Opens the object in `objectKeys`, `objectValues`, `objectNodes`, and `objectCodes`, after checking that no key is there twice, with its members sorted for canonical form.
		*)
		on openObject(level, thePath)
			script Store
				property order : {}
				property sortedKeys : {}
				property sortedValues : {}
				property sortedNodes : {}
				property formattedKeys : {}
				property seenCodes : {}
			end script
			set theCount to count my objectKeys
			if my sortsKeys then
				set Store's order to sortedCodeOrder(my objectCodes)
				-- Equal keys are next to each other in the sorted order.
				repeat with step from 2 to theCount
					if item (item step of Store's order) of my objectCodes = item (item (step - 1) of Store's order) of my objectCodes then
						fail("Duplicate key " & describeKey(item (item step of Store's order) of my objectKeys) & " at " & describePath(thePath))
					end if
				end repeat
			else if theCount ≤ 256 then
				-- `contains` compares the code points natively, which is much faster than a loop.
				repeat with step from 1 to theCount
					set theCodes to item step of my objectCodes
					if Store's seenCodes contains {theCodes} then
						fail("Duplicate key " & describeKey(item step of my objectKeys) & " at " & describePath(thePath))
					end if
					set end of Store's seenCodes to theCodes
				end repeat
			else
				set seenKeys to current application's NSMutableSet's |set|()
				repeat with step from 1 to theCount
					set theKey to "x" & item step of my objectKeys
					if (seenKeys's containsObject:theKey) as boolean then
						fail("Duplicate key " & describeKey(item step of my objectKeys) & " at " & describePath(thePath))
					end if
					seenKeys's addObject:theKey
				end repeat
			end if
			set needsReordering to false
			if my sortsKeys then
				repeat with step from 1 to theCount
					if item step of Store's order is not step then
						set needsReordering to true
						exit repeat
					end if
				end repeat
			end if
			if needsReordering then
				repeat with step from 1 to theCount
					set theIndex to item step of Store's order
					set end of Store's sortedKeys to item theIndex of my objectKeys
					set end of Store's sortedValues to item theIndex of my objectValues
					set end of Store's sortedNodes to item theIndex of my objectNodes
					set end of Store's formattedKeys to formatKeyCodes(item theIndex of my objectKeys, item theIndex of my objectCodes, thePath)
				end repeat
				set my openedKeys to Store's sortedKeys
				set my openedValues to Store's sortedValues
				set my openedNodes to Store's sortedNodes
			else
				set my openedKeys to my objectKeys
				set my openedValues to my objectValues
				set my openedNodes to my objectNodes
				repeat with step from 1 to theCount
					set end of Store's formattedKeys to formatKeyCodes(item step of my objectKeys, item step of my objectCodes, thePath)
				end repeat
			end if
			set my openedFormattedKeys to Store's formattedKeys
			return setOpened(1, level, thePath)
		end openObject

		-- Opens the entries in `valueInHand` of a tagged object, with their display node in `nodeInHand`.
		on openTaggedObject(level, thePath)
			script Store
				property keys : {}
				property values : {}
				property nodes : {}
				property codes : {}
			end script
			if my nodeInHand is missing value or item 1 of my nodeInHand or (count item 3 of my nodeInHand) is not (count my valueInHand) then
				fail("Cannot read the value at " & describePath(thePath))
			end if
			repeat with step from 1 to count my valueInHand
				set pairNode to item step of item 3 of my nodeInHand
				if pairNode is missing value or item 1 of pairNode or (count item 3 of pairNode) is not 2 or class of item step of my valueInHand is not list or (count item step of my valueInHand) is not 2 or not isTextValue(item 1 of item step of my valueInHand) then
					fail("A SOML object's entries are {key, value} lists with text keys, at " & describePath(thePath))
				end if
				set theKey to item 1 of item step of my valueInHand
				set keyCodes to codePoints(theKey)
				set end of Store's keys to theKey
				set end of Store's values to item 2 of item step of my valueInHand
				set end of Store's codes to keyCodes
				set end of Store's nodes to item 2 of item 3 of pairNode
			end repeat
			set my objectKeys to Store's keys
			set my objectValues to Store's values
			set my objectNodes to Store's nodes
			set my objectCodes to Store's codes
			return openObject(level, thePath)
		end openTaggedObject

		(*
		Puts the display node of a value in `nodeInHand`, from the source form that AppleScript shows in the message of a failed coercion. AppleScript has no other way to list the labels of a record. The node is passed through properties, because returning a tree of nodes from a handler takes time in proportion to the tree.
		*)
		on readDisplayTree(theValue)
			set my nodeInHand to missing value
			try
				{SOMLValue:theValue} as «class SOMx»
				return
			on error message
				set displayText to message
			end try
			-- The message is localized, so the display starts where the wrapper does, which is its first “{SOMLValue:”.
			set wrapperOffset to offset of "{SOMLValue:" in displayText
			if wrapperOffset > 1 then
				-- Cutting a long text is slow, so it is only cut when the prefix has a character that the reader reads as structure.
				set prefixCodes to codePoints(text 1 thru (wrapperOffset - 1) of displayText)
				if prefixCodes contains 34 or prefixCodes contains 123 or prefixCodes contains 124 or prefixCodes contains 171 then
					set displayText to text wrapperOffset thru -1 of displayText
				end if
			end if
			set theReader to makeDisplayReader(displayText)
			theReader's readAll()
			set my nodeInHand to theReader's valueNode
		end readDisplayTree

		(*
		Puts the ASCII capitals back in the labels in bars of the record whose display node is `nodeInHand`. A display lowers them in a label that AppleScript made from text, as `decode()` does, so `Content-Type` shows as |content-type|, but the record as a dictionary has the spelling. A record holds no two labels that differ only in ASCII letter case, so each key with capitals belongs to the one label in bars that is the same without them.
		*)
		on restoreBarredLabels(theRecord)
			if item 7 of my nodeInHand is {} then
				return
			end if
			if my capitalPredicate is missing value then
				set my capitalPredicate to current application's NSPredicate's predicateWithFormat:"SELF != SELF.lowercaseString"
			end if
			try
				set capitalKeys to ((current application's NSDictionary's dictionaryWithDictionary:theRecord)'s allKeys()'s filteredArrayUsingPredicate:(my capitalPredicate)) as list
			on error
				-- A value that AppleScriptObjC cannot take, such as a script object, which the writer reports.
				return
			end try
			if capitalKeys = {} then
				return
			end if
			set labelIndexes to current application's NSMutableDictionary's dictionary()
			repeat with labelIndex in item 7 of my nodeInHand
				set labelIndex to contents of labelIndex
				-- The prefix keeps a leading U+FEFF or U+FFFE intact through the bridge.
				set lookupKey to "x" & textFromCodes(foldCase(item labelIndex of item 6 of my nodeInHand))
				labelIndexes's setObject:labelIndex forKey:lookupKey
			end repeat
			repeat with theKey in capitalKeys
				set theKey to contents of theKey
				set theCodes to codePoints(theKey)
				set lookupKey to "x" & textFromCodes(foldCase(theCodes))
				set labelIndex to labelIndexes's objectForKey:lookupKey
				if labelIndex is not missing value then
					set labelIndex to labelIndex as integer
					set item labelIndex of item 2 of my nodeInHand to theKey
					set item labelIndex of item 6 of my nodeInHand to theCodes
				end if
			end repeat
		end restoreBarredLabels

		-- The {key, value} pairs of a record, or the entries of a tagged object, for `entries()`.
		on recordEntries(theRecord)
			script Store
				property values : theRecord as list
				property pairs : {}
			end script
			readDisplayTree(theRecord)
			if my nodeInHand is missing value or not item 1 of my nodeInHand or (count item 2 of my nodeInHand) is not (count Store's values) then
				fail("Cannot read the labels of the record")
			end if
			if item 5 of my nodeInHand is not missing value then
				fail(item 5 of my nodeInHand)
			end if
			set classIndex to item 4 of my nodeInHand
			if classIndex is not 0 then
				set theClass to item classIndex of Store's values
				if theClass is not «class SOMo» then
					fail("entries() expects a record or a SOML object, but got a " & className(theClass))
				end if
				set otherIndex to 1
				if classIndex = 1 then
					set otherIndex to 2
				end if
				set my objectValues to Store's values
				validateTaggedObject(otherIndex, "")
				return item otherIndex of Store's values
			end if
			restoreBarredLabels(theRecord)
			repeat with step from 1 to count Store's values
				set end of Store's pairs to {item step of item 2 of my nodeInHand, item step of Store's values}
			end repeat
			return Store's pairs
		end recordEntries

		-- Converts the values that wait, and joins the output.
		on finish()
			if my pieces is not {} then
				set end of my blocks to my pieces
				set my pieces to {}
			end if
			convertPending()
			repeat with step from 1 to count my blocks
				set item step of my blocks to joinTexts(item step of my blocks, "")
			end repeat
			return joinTexts(my blocks, "")
		end finish

		-- Puts the text of the reals and the dates, converted in a batch, in their places in the output.
		on convertPending()
			script Store
				property inputs : {}
				property results : {}
			end script
			if my pendingReals is not {} then
				repeat with step from 1 to count my pendingReals
					set end of Store's inputs to item 3 of item step of my pendingReals
				end repeat
				set Store's results to callJavaScript(floatJavaScriptContext(), "somlFormatFloats", my floatFormatScript, Store's inputs)
				repeat with step from 1 to count my pendingReals
					set theText to item step of Store's results
					if (length of theText) = 0 then
						fail("Cannot encode NaN at " & describePendingPath(item step of my pendingReals) & ". SOML has no NaN; use missing value for a missing number")
					end if
					set blockIndex to item 1 of item step of my pendingReals
					set pieceIndex to item 2 of item step of my pendingReals
					set item pieceIndex of item blockIndex of my blocks to (item pieceIndex of item blockIndex of my blocks) & theText & linefeed
				end repeat
				set my pendingReals to {}
			end if
			if my pendingDates is not {} then
				set Store's inputs to {}
				repeat with step from 1 to count my pendingDates
					set end of Store's inputs to item 3 of item step of my pendingDates
				end repeat
				set theArray to current application's NSArray's arrayWithArray:(Store's inputs)
				set Store's results to (theArray's valueForKey:"timeIntervalSince1970") as list
				repeat with step from 1 to count my pendingDates
					set epochSeconds to item step of Store's results
					if epochSeconds < -6.21355968E+10 or epochSeconds > 2.53402300799E+11 then
						fail("The date at " & describePendingPath(item step of my pendingDates) & " is outside the years 0001 to 9999 in UTC")
					end if
					set blockIndex to item 1 of item step of my pendingDates
					set pieceIndex to item 2 of item step of my pendingDates
					set item pieceIndex of item blockIndex of my blocks to (item pieceIndex of item blockIndex of my blocks) & formatInstant(epochSeconds, {}) & linefeed
				end repeat
				set my pendingDates to {}
			end if
		end convertPending

		-- The grammar reader is created only for tagged scalar values.
		on scalarReader()
			if my taggedReader is missing value then
				set my taggedReader to makeReader("")
			end if
			return my taggedReader
		end scalarReader
	end script
	return Writer
end makeWriter

(*
A key as SOML writes it: bare when it is one or more letters, digits, “_”, and “-”, and otherwise quoted.
*)
on formatKeyCodes(theKey, theCodes, thePath)
	if my isBareKeyText(theKey, theCodes) then
		return theKey
	end if
	if length of thePath = 0 then
		set thePath to "the root"
	end if
	return formatStringCodes(theKey, theCodes, "Cannot encode a key at " & thePath)
end formatKeyCodes

(*
A string as SOML writes it: '...' unless it holds a ', a tab, a line feed, or another control character, and then "..." with escapes. Errors with number 2 for a carriage return or a lone surrogate, with a message that starts with `theName`, such as “Cannot encode the string at a”.
*)
on formatStringCodes(theText, theCodes, theName)
	script Store
		property source : theCodes
	end script
	set needsEscapes to false
	set needsUnicodeValidation to false
	set theCount to count Store's source
	repeat with step from 1 to theCount
		set theCode to item step of Store's source
		-- Most characters are letters and digits, which one or two comparisons rule out.
		if theCode < 40 then
			if theCode < 32 or theCode = 39 then
				if theCode = 13 then
					error my sanitize(theName & ", because it contains a carriage return (U+000D), which SOML cannot represent") number my unsupportedValueErrorNumber
				end if
				set needsEscapes to true
			end if
		else if theCode ≥ 127 and (theCode = 127 or (theCode ≥ 55296 and theCode ≤ 57343)) then
			if theCode ≥ 55296 then
				error my sanitize(theName & ", because it contains a lone surrogate") number my unsupportedValueErrorNumber
			end if
			set needsEscapes to true
		else if theCode > 65535 then
			set needsUnicodeValidation to true
		end if
	end repeat
	if needsUnicodeValidation or theCount is not length of theText then
		-- AppleScript combines a high surrogate with any following character in `id of`, so an apparent astral scalar needs a UTF-8 check, and so does a merged surrogate, whose codes end up one fewer than the text has UTF-16 units. Astral characters shorten the codes the same way, so any difference needs the check. The prefix prevents leading U+FEFF or U+FFFE from changing in the bridge.
		set nativeText to my nativeString(theText)
		if (nativeText's dataUsingEncoding:(current application's NSUTF8StringEncoding)) is missing value then
			error my sanitize(theName & ", because it contains a lone surrogate") number my unsupportedValueErrorNumber
		end if
	end if
	if not needsEscapes then
		return "'" & theText & "'"
	end if
	return my quoteEscapedText(theText, Store's source, false)
end formatStringCodes

(*
The indexes of code point lists in the order of their Unicode scalar values, by a merge sort.
*)
on sortedCodeOrder(theCodes)
	script Store
		property codes : theCodes
		property order : {}
		property merged : {}
	end script
	set theCount to count Store's codes
	set isOrdered to true
	repeat with step from 1 to theCount
		set end of Store's order to step
		if isOrdered and step > 1 then
			set isOrdered to my compareCodes(item (step - 1) of Store's codes, item step of Store's codes) ≤ 0
		end if
	end repeat
	if isOrdered then
		return Store's order
	end if
	set width to 1
	repeat while width < theCount
		set Store's merged to {}
		set firstIndex to 1
		repeat while firstIndex ≤ theCount
			set middleIndex to firstIndex + width
			set endIndex to firstIndex + 2 * width
			if middleIndex > theCount + 1 then
				set middleIndex to theCount + 1
			end if
			if endIndex > theCount + 1 then
				set endIndex to theCount + 1
			end if
			-- Adjacent runs that are already in order need no element-by-element comparisons.
			if middleIndex = endIndex or my compareCodes(item (item (middleIndex - 1) of Store's order) of Store's codes, item (item middleIndex of Store's order) of Store's codes) ≤ 0 then
				repeat with step from firstIndex to endIndex - 1
					set end of Store's merged to item step of Store's order
				end repeat
			else
				set leftIndex to firstIndex
				set rightIndex to middleIndex
				repeat while leftIndex < middleIndex and rightIndex < endIndex
					if my compareCodes(item (item rightIndex of Store's order) of Store's codes, item (item leftIndex of Store's order) of Store's codes) < 0 then
						set end of Store's merged to item rightIndex of Store's order
						set rightIndex to rightIndex + 1
					else
						set end of Store's merged to item leftIndex of Store's order
						set leftIndex to leftIndex + 1
					end if
				end repeat
				repeat with step from leftIndex to middleIndex - 1
					set end of Store's merged to item step of Store's order
				end repeat
				repeat with step from rightIndex to endIndex - 1
					set end of Store's merged to item step of Store's order
				end repeat
			end if
			set firstIndex to endIndex
		end repeat
		set Store's order to Store's merged
		set width to width * 2
	end repeat
	return Store's order
end sortedCodeOrder

(*
Whether text ends in an odd number of backslashes. Only suffix blocks are converted to code points, so a long string with a short escaped suffix needs no full scan.
*)
on hasOddTrailingBackslashes(theText)
	set lastIndex to length of theText
	set trailing to 0
	repeat while lastIndex > 0
		set firstIndex to lastIndex - 511
		if firstIndex < 1 then
			set firstIndex to 1
		end if
		script Store
			property codes : codePoints(text firstIndex thru lastIndex of theText)
		end script
		repeat with step from (count Store's codes) to 1 by -1
			if item step of Store's codes is not 92 then
				return trailing mod 2 = 1
			end if
			set trailing to trailing + 1
		end repeat
		set lastIndex to firstIndex - 1
	end repeat
	return trailing mod 2 = 1
end hasOddTrailingBackslashes

(*
Reads the display of a value, such as {a:1, |b c|:{d:"x"}, name:"y"}, into a tree of the records and lists in it. A node is {isRecord, keys, child nodes, index of a `class` label or 0, a problem or missing value, the code points of the keys, the indexes of the labels in bars}, with a child node for each item, which is missing value for a value that is neither a record nor a list.

The display is split at its quotes, so that the text of a string is skipped without reading it: the pieces alternate between the structure and the strings, except where an escaped quote is inside a string, or a quote is inside a |…| label or «…» data.
*)
on makeDisplayReader(displayText)
	set thePieces to my splitText(displayText, "\"")
	script DisplayReader
		property pieces : thePieces
		property pieceCount : count thePieces
		property sourceCodes : {}
		property openNodes : {}
		property nodeDepth : 0
		property rootNode : missing value
		-- The node of the value, which `readAll` finds.
		property valueNode : missing value
		-- Whether the innermost open node is a record.
		property isCurrentRecord : false
		property isCurrentEmpty : true
		-- The state of the scan, which goes on from one piece to the next.
		property isInString : false
		property isInBars : false
		property isInRaw : false
		property isEscaped : false
		-- 0: not reading a label; 1: a label may start here, after `{`; 2: a label must start here, after `, ` in a record.
		property labelState : 0
		property labelCodes : {}
		-- 0: a word, such as a keyword; 1: |…|; 2: «…».
		property labelKind : 0

		on readAll()
			repeat with pieceIndex from 1 to my pieceCount
				set thePiece to item pieceIndex of my pieces
				if my isInString then
					-- The piece is the text of a string. An odd number of backslashes at its end escapes the quote after it.
					considering case, diacriticals, hyphens, punctuation and white space
						if thePiece ends with "\\" then
							set my isInString to hasOddTrailingBackslashes(thePiece)
						else
							set my isInString to false
						end if
					end considering
				else
					if length of thePiece > 512 then
						set isQuoteHandled to scanLongPiece(thePiece)
					else
						set my sourceCodes to codePoints(thePiece)
						set isQuoteHandled to scanPiece()
					end if
					if pieceIndex < my pieceCount and not isQuoteHandled then
						quoteAfterPiece()
					end if
				end if
				if my nodeDepth = 0 and my rootNode is not missing value then
					exit repeat
				end if
			end repeat
			if my nodeDepth is not 0 or my rootNode is missing value or (count item 3 of my rootNode) = 0 then
				return
			end if
			-- The root is the value of {SOMLValue:…}.
			set my valueNode to item 1 of item 3 of my rootNode
		end readAll

		(*
		Scans a long piece in parts split at “, ”, which a display has between the items of every record and list, with the “, ” put back, so the scan sees the same codes. The code points of long text take time out of proportion to its length, and the parts are short. A quote in a piece is one that a combining mark follows, and it starts a string that runs to the end of the piece, so a piece with one is scanned whole.
		*)
		on scanLongPiece(thePiece)
			-- A literal native search finds quotes followed by combining marks too.
			set theString to nativeString(thePiece)
			if ((theString's rangeOfString:"\"" options:(current application's NSLiteralSearch))'s location) as real < 1.0E+18 then
				set my sourceCodes to codePoints(thePiece)
				return scanPiece()
			end if
			script Store
				property parts : splitText(thePiece, ", ")
			end script
			set partCount to count Store's parts
			repeat with step from 1 to partCount
				set my sourceCodes to codePoints(item step of Store's parts)
				if step < partCount then
					set end of my sourceCodes to 44
					set end of my sourceCodes to 32
				end if
				scanPiece()
			end repeat
			return false
		end scanLongPiece

		-- A quote between two pieces, outside a string.
		on quoteAfterPiece()
			if my isInBars or my isInRaw then
				if my labelState > 0 then
					set end of my labelCodes to 34
				end if
				return
			end if
			if my labelState = 1 then
				-- A string after `{` makes the brace a list.
				set my labelState to 0
				set my labelCodes to {}
				set my labelKind to 0
			end if
			set my isCurrentEmpty to false
			set my isInString to true
		end quoteAfterPiece

		on scanPiece()
			set theCount to count my sourceCodes
			set step to 1
			repeat while step ≤ theCount
				if my isInBars or my isInRaw or my labelState > 0 then
					set theCode to item step of my sourceCodes
					if my isInBars then
						if my isEscaped then
							set my isEscaped to false
							if my labelState > 0 then
								-- A label escapes tabs, line feeds, carriage returns, backslashes, and bars.
								if theCode = 116 then
									set end of my labelCodes to 9
								else if theCode = 110 then
									set end of my labelCodes to 10
								else if theCode = 114 then
									set end of my labelCodes to 13
								else
									set end of my labelCodes to theCode
								end if
							end if
						else if theCode = 92 then
							set my isEscaped to true
						else if theCode = 124 then
							set my isInBars to false
						else
							-- The characters up to the next `\` or `|` are read in one run.
							set runEnd to step + 1
							repeat while runEnd ≤ theCount
								set theCode to item runEnd of my sourceCodes
								if theCode = 92 or theCode = 124 then
									exit repeat
								end if
								set runEnd to runEnd + 1
							end repeat
							if my labelState > 0 then
								set my labelCodes to (my labelCodes) & (items step thru (runEnd - 1) of my sourceCodes)
							end if
							set step to runEnd - 1
						end if
					else if my isInRaw then
						if theCode = 187 then
							if my labelState > 0 then
								set end of my labelCodes to theCode
							end if
							set my isInRaw to false
						else
							-- The characters up to the closing `»` are read in one run.
							set runEnd to step + 1
							repeat while runEnd ≤ theCount
								if item runEnd of my sourceCodes = 187 then
									exit repeat
								end if
								set runEnd to runEnd + 1
							end repeat
							if my labelState > 0 then
								set my labelCodes to (my labelCodes) & (items step thru (runEnd - 1) of my sourceCodes)
							end if
							set step to runEnd - 1
						end if
					else if theCode = 34 then
						quoteInPiece(step)
						return true
					else if my labelKind = 0 and ((theCode ≥ 97 and theCode ≤ 122) or (theCode ≥ 65 and theCode ≤ 90) or (theCode ≥ 48 and theCode ≤ 57) or theCode = 95) then
						-- Most labels are words, whose characters are read in one run here, as `readLabelCode` would read them one at a time.
						set runEnd to step + 1
						repeat while runEnd ≤ theCount
							set theCode to item runEnd of my sourceCodes
							if not ((theCode ≥ 97 and theCode ≤ 122) or (theCode ≥ 65 and theCode ≤ 90) or (theCode ≥ 48 and theCode ≤ 57) or theCode = 95 or theCode = 32) then
								exit repeat
							end if
							set runEnd to runEnd + 1
						end repeat
						set my labelCodes to (my labelCodes) & (items step thru (runEnd - 1) of my sourceCodes)
						set my isCurrentEmpty to false
						set step to runEnd - 1
					else
						readLabelCode(theCode)
					end if
					set step to step + 1
				else
					-- Most of a display is the text of values, which only these characters end.
					repeat while step ≤ theCount
						set theCode to item step of my sourceCodes
						if theCode < 48 then
							if theCode = 44 or theCode = 34 then
								exit repeat
							end if
						else if theCode > 122 then
							if theCode = 123 or theCode = 125 or theCode = 171 or theCode = 124 then
								exit repeat
							end if
						end if
						set step to step + 1
					end repeat
					if step > theCount then
						exit repeat
					end if
					if theCode = 34 then
						-- A quote that a combining mark follows is not split at, so the rest of the piece is the start of a string.
						quoteInPiece(step)
						return true
					end if
					readStructureCode(theCode)
					set step to step + 1
				end if
			end repeat
			return false
		end scanPiece

		-- A quote inside a piece opens a string that runs to the end of the piece. The string goes on after the piece when its text there ends with an odd number of backslashes, which escape the quote at the end of the piece.
		on quoteInPiece(step)
			quoteAfterPiece()
			set trailing to 0
			repeat with theIndex from (count my sourceCodes) to step + 1 by -1
				if item theIndex of my sourceCodes is not 92 then
					exit repeat
				end if
				set trailing to trailing + 1
			end repeat
			set my isInString to trailing mod 2 = 1
		end quoteInPiece

		on readLabelCode(theCode)
			-- A brace is empty when a `}` follows it directly, which is the only time a `}` comes first.
			if my isCurrentEmpty and theCode is not 125 then
				set my isCurrentEmpty to false
			end if
			if theCode = 58 then
				-- A label in bars may be empty: ||.
				if my labelCodes is not {} or my labelKind = 1 then
					addLabel()
					return
				end if
			else if theCode = 124 and my labelCodes = {} then
				set my labelKind to 1
				set my isInBars to true
				return
			else if theCode = 171 and my labelCodes = {} then
				set my labelKind to 2
				set my isInRaw to true
				set end of my labelCodes to theCode
				return
			else if my labelKind = 0 and ((theCode ≥ 97 and theCode ≤ 122) or (theCode ≥ 65 and theCode ≤ 90) or (theCode ≥ 48 and theCode ≤ 57) or theCode = 95 or (theCode = 32 and my labelCodes is not {})) then
				set end of my labelCodes to theCode
				return
			else if theCode = 32 and my labelCodes = {} then
				return
			end if
			-- No label here, so the brace is a list, and what was read is its first item.
			if my labelCodes is not {} then
				set my isCurrentEmpty to false
			end if
			set my labelState to 0
			set my labelCodes to {}
			set my labelKind to 0
			readStructureCode(theCode)
		end readLabelCode

		on addLabel()
			if my labelState = 1 then
				-- The first label makes the brace a record.
				set item 1 of item (my nodeDepth) of my openNodes to true
				set my isCurrentRecord to true
			end if
			set my labelState to 0
			set my isCurrentEmpty to false
			set theCodes to my labelCodes
			set theKey to textFromCodes(theCodes)
			if my labelKind = 2 then
				set item 5 of item (my nodeDepth) of my openNodes to "The record label " & theKey & " has no name. Write the label in bars, as in |name|"
			else if my labelKind = 0 and theCodes = {99, 108, 97, 115, 115} then
				set item 4 of item (my nodeDepth) of my openNodes to (count item 2 of item (my nodeDepth) of my openNodes) + 1
			end if
			set end of item 2 of item (my nodeDepth) of my openNodes to theKey
			set end of item 6 of item (my nodeDepth) of my openNodes to theCodes
			if my labelKind = 1 then
				set end of item 7 of item (my nodeDepth) of my openNodes to count item 2 of item (my nodeDepth) of my openNodes
			end if
			set my labelCodes to {}
			set my labelKind to 0
		end addLabel

		on readStructureCode(theCode)
			if theCode = 123 then
				openNode()
			else if theCode = 125 then
				closeNode()
			else if theCode = 44 then
				set end of item 3 of item (my nodeDepth) of my openNodes to missing value
				if my isCurrentRecord then
					set my labelState to 2
					set my labelCodes to {}
					set my labelKind to 0
				end if
			else if theCode = 171 then
				set my isInRaw to true
			else if theCode = 124 then
				set my isInBars to true
			end if
		end readStructureCode

		on openNode()
			set theNode to {false, {}, {missing value}, 0, missing value, {}, {}}
			if my nodeDepth > 0 then
				set my isCurrentEmpty to false
				set item -1 of item 3 of item (my nodeDepth) of my openNodes to theNode
			end if
			set my nodeDepth to (my nodeDepth) + 1
			if my nodeDepth > (count my openNodes) then
				set end of my openNodes to theNode
			else
				set item (my nodeDepth) of my openNodes to theNode
			end if
			if my rootNode is missing value then
				set my rootNode to theNode
			end if
			-- Makes the innermost open node the current one. Its lists are always taken through `openNodes`, because assigning a long list of nodes to a property again and again takes time in proportion to the list.
			set my isCurrentRecord to item 1 of item (my nodeDepth) of my openNodes
			set my isCurrentEmpty to true
			set my labelState to 1
			set my labelCodes to {}
			set my labelKind to 0
		end openNode

		on closeNode()
			-- An empty brace has no item.
			if my isCurrentEmpty then
				set item 3 of item (my nodeDepth) of my openNodes to {}
			end if
			set my labelState to 0
			set item (my nodeDepth) of my openNodes to missing value
			set my nodeDepth to (my nodeDepth) - 1
			if my nodeDepth > 0 then
				set my isCurrentRecord to item 1 of item (my nodeDepth) of my openNodes
				set my isCurrentEmpty to false
			end if
		end closeNode

	end script
	return DisplayReader
end makeDisplayReader
