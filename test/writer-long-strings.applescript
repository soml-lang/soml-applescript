(*
Long strings retain exact SOML escaping across the native-formatting threshold, including Unicode prefixes, rare controls, and invalid-text diagnostics.
*)
use AppleScript version "2.8"
use framework "Foundation"
use soml : script "SOML"

property checks : 0

on checkEncoding(theText, expectedValue)
	set expectedText to "payload: " & expectedValue & linefeed
	set nativeExpected to current application's NSString's stringWithString:expectedText
	repeat with isCanonical in {false, true}
		if contents of isCanonical then
			set encodedText to soml's encodeCanonical({payload:theText})
		else
			set encodedText to soml's encode({payload:theText})
		end if
		set checks to checks + 1
		if not (nativeExpected's isEqualToString:encodedText) as boolean then
			error "Long string output changed" number 99
		end if
		set decodedText to item 2 of item 1 of soml's entries(soml's decode(encodedText))
		set nativeOriginal to current application's NSString's stringWithString:("x" & theText)
		set checks to checks + 1
		if not (nativeOriginal's isEqualToString:("x" & decodedText)) as boolean then
			error "Long string round trip changed" number 99
		end if
	end repeat
end checkEncoding

on checkRejected(theText, expectedReason)
	repeat with isCanonical in {false, true}
		try
			if contents of isCanonical then
				soml's encodeCanonical({payload:theText})
			else
				soml's encode({payload:theText})
			end if
			error "Encoded invalid long text" number 99
		on error message number errorNumber
			set checks to checks + 1
			if errorNumber is not 2 or message does not contain "payload" or message does not contain expectedReason then
				error "Long string diagnostic changed: " & message number 99
			end if
		end try
	end repeat
end checkRejected

on run
	set checks to 0
	set nativeSeed to current application's NSString's stringWithString:"a"
	repeat with stringLength in {512, 513, 20001}
		set padding to (nativeSeed's stringByPaddingToLength:((contents of stringLength) - 1) withString:"a" startingAtIndex:0) as text
		checkEncoding(padding & "'", quote & padding & "'" & quote)
	end repeat
	set padding to (nativeSeed's stringByPaddingToLength:600 withString:"a" startingAtIndex:0) as text
	set controlText to ""
	set escapedControls to ""
	set escapeCharacter to character id 92
	repeat with controlCode in {0, 1, 8, 11, 12, 14, 31, 127}
		set controlText to controlText & character id (contents of controlCode)
	end repeat
	repeat with hexadecimalCode in {"0", "1", "8", "b", "c", "e", "1f", "7f"}
		set escapedControls to escapedControls & escapeCharacter & "u{" & contents of hexadecimalCode & "}"
	end repeat
	set suffixText to "'" & quote & escapeCharacter & tab & linefeed & controlText
	set escapedSuffix to "'" & escapeCharacter & quote & escapeCharacter & escapeCharacter & escapeCharacter & "t" & escapeCharacter & "n" & escapedControls
	repeat with prefixText in {"", character id 65279, character id 65534, character id 769, "🦄"}
		set originalText to (contents of prefixText) & padding & suffixText
		set expectedValue to quote & (contents of prefixText) & padding & escapedSuffix & quote
		checkEncoding(originalText, expectedValue)
	end repeat
	checkEncoding(padding & "'" & padding & "'", quote & padding & "'" & padding & "'" & quote)
	checkEncoding(padding, "'" & padding & "'")
	checkRejected(padding & "'" & return, "carriage return")
	set nativeAstral to current application's NSString's stringWithString:"🦄"
	repeat with malformedText in {(nativeAstral's substringToIndex:1) as text, (nativeAstral's substringFromIndex:1) as text}
		checkRejected(padding & "'" & contents of malformedText & "q", "lone surrogate")
	end repeat
	return (checks as text) & " long string writer checks passed"
end run
