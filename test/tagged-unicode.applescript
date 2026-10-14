(*
Tagged scalar text must contain Unicode scalar values before parsing reconstructs it. Malformed native text reports the documented helper and encoder errors; valid scalar spellings and valid Unicode grammar errors retain their boundaries.
*)
use AppleScript version "2.8"
use framework "Foundation"
use scripting additions
use soml : script "SOML"
property failures : {}
property checks : 0

on expectError(theName, operation, taggedValue, expectedNumber)
	set checks to checks + 1
	try
		if operation is "toNumber" then
			soml's toNumber(taggedValue)
		else if operation is "toDate" then
			soml's toDate(taggedValue)
		else if operation is "toSeconds" then
			soml's toSeconds(taggedValue)
		else if operation is "encode" then
			soml's encode({payload:taggedValue})
		else
			soml's encodeCanonical({payload:taggedValue})
		end if
		set end of failures to theName & ": accepted invalid tagged text"
	on error message number errorNumber
		if errorNumber is not expectedNumber then
			set end of failures to theName & ": expected " & expectedNumber & ", got " & errorNumber & " " & message
		end if
	end try
end expectError

set nativeAstral to current application's NSString's stringWithString:(character id 128512)
set highSurrogate to (nativeAstral's substringToIndex:1) as text
set lowSurrogate to (nativeAstral's substringFromIndex:1) as text
set surrogateFixtures to {{"high", highSurrogate, 55357}, {"low", lowSurrogate, 56832}}
repeat with surrogateFixture in surrogateFixtures
	set {surrogateName, surrogateText, expectedUnit} to contents of surrogateFixture
	set nativeSurrogate to (current application's NSString's stringWithString:("x" & surrogateText))'s substringFromIndex:1
	if class of surrogateText is not text or (nativeSurrogate's |length|()) as integer is not 1 or (nativeSurrogate's characterAtIndex:0) as integer is not expectedUnit then
		error "Surrogate fixture changed its class or exact UTF-16 unit"
	end if
	repeat with paddingLength in {0, 39, 41}
		set prefixText to ""
		repeat paddingLength times
			set prefixText to prefixText & "q"
		end repeat
		set malformedText to prefixText & surrogateText & "q"
		set nativeText to (current application's NSString's stringWithString:("x" & malformedText))'s substringFromIndex:1
		if (nativeText's dataUsingEncoding:(current application's NSUTF8StringEncoding) allowLossyConversion:false) is not missing value then
			error "Tagged-text fixture no longer contains a genuine lone surrogate"
		end if
		repeat with tagCase in {{SOML int, "toNumber"}, {SOML instant, "toDate"}, {SOML duration, "toSeconds"}}
			set {tagClass, helperName} to contents of tagCase
			set taggedValue to {class:tagClass, value:malformedText}
			set taggedNative to (current application's NSString's stringWithString:("x" & value of taggedValue))'s substringFromIndex:1
			if class of value of taggedValue is not text or (taggedNative's |length|()) as integer is not paddingLength + 2 or (taggedNative's characterAtIndex:(paddingLength as integer)) as integer is not expectedUnit or (taggedNative's dataUsingEncoding:(current application's NSUTF8StringEncoding) allowLossyConversion:false) is not missing value then
				error "Tag construction changed the actual malformed Unicode text fixture"
			end if
			set context to surrogateName & " surrogate, prefix " & paddingLength & ", " & helperName
			expectError(context, helperName, taggedValue, -1703)
			expectError(context & " encode", "encode", taggedValue, 2)
			expectError(context & " canonical", "canonical", taggedValue, 2)
		end repeat
	end repeat
end repeat
-- Valid Unicode can still be invalid scalar grammar; it must follow the normal invalid-value path.
repeat with invalidUnicode in {"é🦄", "e" & character id 769, (character id 65279) & "invalid", (character id 65534) & "invalid"}
	set invalidUnicode to contents of invalidUnicode
	set nativeText to current application's NSString's stringWithString:("x" & invalidUnicode)
	if (nativeText's dataUsingEncoding:(current application's NSUTF8StringEncoding) allowLossyConversion:false) is missing value then
		error "Valid Unicode grammar fixture became malformed"
	end if
	repeat with tagCase in {{SOML int, "toNumber"}, {SOML instant, "toDate"}, {SOML duration, "toSeconds"}}
		set {tagClass, helperName} to contents of tagCase
		set taggedValue to {class:tagClass, value:invalidUnicode}
		expectError("Valid Unicode invalid grammar " & helperName, helperName, taggedValue, -1703)
		expectError("Valid Unicode invalid grammar encode " & helperName, "encode", taggedValue, 2)
		expectError("Valid Unicode invalid grammar canonical " & helperName, "canonical", taggedValue, 2)
	end repeat
end repeat

-- Noncanonical ASCII spellings remain valid, with independently specified native classes and exact canonical text.
set validCases to {{{class:SOML int, value:"0xFF"}, "toNumber", integer, "255"}, {{class:SOML instant, value:"2026-09-19T14:00:00+02:00"}, "toDate", date, "2026-09-19T12:00:00Z"}, {{class:SOML duration, value:"1.50h"}, "toSeconds", real, "1h30m"}}
repeat with validCase in validCases
	set {taggedValue, helperName, expectedClass, canonicalText} to contents of validCase
	set checks to checks + 1
	try
		if helperName is "toNumber" then
			set actualValue to soml's toNumber(taggedValue)
			if actualValue is not 255 then
				error "Changed the valid integer value"
			end if
		else if helperName is "toDate" then
			set actualValue to soml's toDate(taggedValue)
			set expectedArray to "[" & linefeed & tab & canonicalText & linefeed & "]" & linefeed
			if id of soml's encodeCanonical({actualValue}) is not id of expectedArray then
				error "Changed the valid instant value"
			end if
		else
			set actualValue to soml's toSeconds(taggedValue)
			if actualValue is not 5400.0 then
				error "Changed the valid duration value"
			end if
		end if
		if class of actualValue is not expectedClass then
			error "Changed the native helper result class"
		end if
	on error message number errorNumber
		set end of failures to "Valid ASCII " & helperName & ": " & errorNumber & " " & message
	end try
	repeat with isCanonical in {false, true}
		set checks to checks + 1
		try
			if contents of isCanonical then
				set encoded to soml's encodeCanonical({payload:taggedValue})
			else
				set encoded to soml's encode({payload:taggedValue})
			end if
			if id of encoded is not id of ("payload: " & canonicalText & linefeed) then
				error "Changed valid tagged scalar output"
			end if
		on error message number errorNumber
			set end of failures to "Valid ASCII encoding " & helperName & ": " & errorNumber & " " & message
		end try
	end repeat
end repeat

if failures is not {} then
	error soml's joinTexts(failures, linefeed)
end if
return (checks as text) & " tagged Unicode checks passed"
