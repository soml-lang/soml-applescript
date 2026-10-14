(*
Caller comparison settings must not change a numeric error's suggested sign or remove keys from the documented writer error path. Expected reasons, positions, and paths are specified independently of the library's comparisons.
*)
use AppleScript version "2.8"
use framework "JavaScriptCore"
use scripting additions
use soml : script "SOML"
property failures : {}
property checks : 0

on checkDocumentError(theName, sourceText, expectedReason, expectedLine, expectedColumn)
	set checks to checks + 1
	try
		soml's decode(sourceText)
		set end of failures to theName & ": accepted an out-of-range float"
	on error message number errorNumber from details
		if errorNumber is not 1 then
			set end of failures to theName & ": expected error 1, got " & errorNumber
		else if |line| of details is not expectedLine or |column| of details is not expectedColumn or id of reason of details is not id of expectedReason or id of message is not id of (expectedReason & " at line " & expectedLine & ", column " & expectedColumn) then
			set end of failures to theName & ": changed exact reason or position: " & message
		end if
	end try
end checkDocumentError

on testFloatErrors(contextName)
	set positiveReason to "1e999 is too large to be a finite float. Use infinity if you mean it"
	set negativeReason to "-1e999 is too large to be a finite float. Use -infinity if you mean it"
	set underflowReason to "1e-999 is too small to be told apart from zero. Write 0.0 if you mean zero"
	checkDocumentError(contextName & " positive overflow", "[1e999]", positiveReason, 1, 2)
	checkDocumentError(contextName & " negative overflow", "[-1e999]", negativeReason, 1, 2)
	-- A prior valid float and a later syntax error must leave the overflow's sign and position intact.
	checkDocumentError(contextName & " pending positive overflow", "[0.5, 1e999, ?]", positiveReason, 1, 7)
	checkDocumentError(contextName & " pending negative overflow", "[0.5, -1e999, ?]", negativeReason, 1, 7)
	checkDocumentError(contextName & " pending underflow control", "[0.5, 1e-999, ?]", underflowReason, 1, 7)
	set unicodePrefix to "/* é🦄" & linefeed & character id 769 & "comment */" & linefeed
	checkDocumentError(contextName & " combining comment prefix", unicodePrefix & "[1e999, ?]", positiveReason, 3, 2)
end testFloatErrors

on checkWriterError(theName, theValue, canonicalMode, expectedMessage)
	set checks to checks + 1
	try
		if canonicalMode then
			soml's encodeCanonical(theValue)
		else
			soml's encode(theValue)
		end if
		set end of failures to theName & ": accepted an unsupported value"
	on error message number errorNumber
		if errorNumber is not 2 or id of message is not id of expectedMessage then
			set end of failures to theName & ": expected exact error 2, got " & errorNumber & " " & message
		end if
	end try
end checkWriterError

on testWriterPaths(contextName, nativeNaN)
	-- Empty keys have a documented '' path component. The other expected paths retain their exact key text.
	set pathCases to {{"_", "_.leaf", "_"}, {"-", "-.leaf", "-"}, {" ", " .leaf", " "}, {"...", "....leaf", "..."}, {"", "''.leaf", "''"}, {"ordinary", "ordinary.leaf", "ordinary"}, {"é🦄", "é🦄.leaf", "é🦄"}}
	repeat with caseIndex from 1 to count pathCases
		set {parentKey, expectedPath, expectedParentPath} to item caseIndex of pathCases
		set carriageReturnValue to soml's fromEntries({{parentKey, {leaf:character id 13}}})
		set nanValue to soml's fromEntries({{parentKey, {leaf:nativeNaN}}})
		set unsupportedKey to soml's fromEntries({{"bad" & character id 13 & "key", 1}})
		set keyValue to soml's fromEntries({{parentKey, unsupportedKey}})
		set carriageReturnMessage to "Cannot encode the string at " & expectedPath & ", because it contains a carriage return (U+000D), which SOML cannot represent"
		set nanMessage to "Cannot encode NaN at " & expectedPath & ". SOML has no NaN; use missing value for a missing number"
		set keyMessage to "Cannot encode a key at " & expectedParentPath & ", because it contains a carriage return (U+000D), which SOML cannot represent"
		repeat with canonicalMode in {false, true}
			set canonicalMode to contents of canonicalMode
			set caseName to contextName & " path " & caseIndex & " canonical " & canonicalMode
			checkWriterError(caseName & " CR", carriageReturnValue, canonicalMode, carriageReturnMessage)
			-- NaN reaches the writer's deferred real conversion, rather than immediate string validation.
			checkWriterError(caseName & " NaN", nanValue, canonicalMode, nanMessage)
			checkWriterError(caseName & " CR key", keyValue, canonicalMode, keyMessage)
		end repeat
	end repeat
end testWriterPaths

on testValidControls(contextName)
	set sourceText to "/* é🦄" & linefeed & character id 769 & "comment */" & linefeed & "[" & linefeed & "'''" & linefeed & "e" & character id 769 & linefeed & character id 769 & "🦄" & linefeed & "'''" & linefeed & "]"
	set expectedText to "[" & linefeed & tab & "\"e" & character id 769 & "\\n" & character id 769 & "🦄\"" & linefeed & "]" & linefeed
	set cases to {{sourceText, expectedText}, {"[0.5, {'é': 'kept'}]", "[" & linefeed & tab & "0.5" & linefeed & tab & "{" & linefeed & tab & tab & "'é': 'kept'" & linefeed & tab & "}" & linefeed & "]" & linefeed}}
	repeat with caseIndex from 1 to count cases
		set checks to checks + 1
		try
			set actual to soml's encodeCanonical(soml's decode(item 1 of item caseIndex of cases))
			if id of actual is not id of item 2 of item caseIndex of cases then
				set end of failures to contextName & " valid control " & caseIndex & ": changed exact value"
			end if
		on error message number errorNumber
			set end of failures to contextName & " valid control " & caseIndex & ": " & errorNumber & " " & message
		end try
	end repeat
end testValidControls

on testContext(contextName, nativeNaN)
	testFloatErrors(contextName)
	testWriterPaths(contextName, nativeNaN)
	testValidControls(contextName)
end testContext

on run
	set failures to {}
	set checks to 0
	set context to current application's JSContext's new()
	set nativeNaN to ((context's evaluateScript:"NaN")'s toDouble()) as real
	if class of nativeNaN is not real then
		error "Fixture did not produce a native real"
	end if
	considering case, diacriticals, hyphens, punctuation and white space
		testContext("considering", nativeNaN)
	end considering
	ignoring hyphens
		testContext("ignoring hyphens", nativeNaN)
	end ignoring
	ignoring punctuation and white space
		testContext("ignoring punctuation and white space", nativeNaN)
	end ignoring
	ignoring case, diacriticals, hyphens, punctuation and white space
		testContext("ignoring all", nativeNaN)
	end ignoring
	if failures is not {} then
		error ((count failures) as text) & " of " & (checks as text) & " caller diagnostic checks failed:" & linefeed & soml's joinTexts(failures, linefeed)
	end if
	return (checks as text) & " caller diagnostic checks passed"
end run
