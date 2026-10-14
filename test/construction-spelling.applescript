(*
Constructing an outer record must preserve existing nested record labels, even when the process registered another spelling earlier.
*)
use AppleScript version "2.8"
use scripting additions
use soml : script "SOML"
property failures : {}
property testCount : 0

on checkKey(theRecord, expectedKey, expectedValue)
	set testCount to testCount + 1
	set actualPairs to soml's entries(theRecord)
	if id of item 1 of item 1 of actualPairs is not id of expectedKey or item 2 of item 1 of actualPairs is not expectedValue then
		set end of failures to "Changed the nested label " & expectedKey
	end if
end checkKey

on checkPairs(theName, actual, expected)
	set testCount to testCount + 1
	considering case, diacriticals, hyphens, punctuation and white space
		if actual is not expected then
			set end of failures to theName
		end if
	end considering
end checkPairs

on checkText(theName, actual, expected)
	set testCount to testCount + 1
	if id of actual is not id of expected then
		set end of failures to theName
	end if
end checkText

on testMultipleNestedLabels()
	set originalRecord to {|Profile-Name|:"human", |Stable-Count|:2, |École-Name|:4, |UnicodeÉ-Name|:5}
	soml's decode("profile-name:0" & linefeed & "stable-count:0" & linefeed & "'École-name':0" & linefeed & "'unicodeÉ-name':0")
	set expectedPairs to {{"Profile-Name", "human"}, {"Stable-Count", 2}, {"École-Name", 4}, {"UnicodeÉ-Name", 5}}
	checkPairs("Literal Unicode and distinct key spellings changed before construction", soml's entries(originalRecord), expectedPairs)
	set made to soml's fromEntries({{"container", {originalRecord}}})
	set actualRecord to item 1 of item 2 of item 1 of soml's entries(made)
	checkPairs("Distinct nested labels or value associations changed", soml's entries(actualRecord), expectedPairs)
	checkText("Distinct nested label output changed", soml's encode(actualRecord), "Profile-Name: 'human'" & linefeed & "Stable-Count: 2" & linefeed & "'École-Name': 4" & linefeed & "'UnicodeÉ-Name': 5" & linefeed)
	checkText("Distinct nested canonical labels or value associations changed", soml's encodeCanonical(actualRecord), "Profile-Name: 'human'" & linefeed & "Stable-Count: 2" & linefeed & "'UnicodeÉ-Name': 5" & linefeed & "'École-Name': 4" & linefeed)
end testMultipleNestedLabels

on testRootNestedCaseInteraction()
	set originalRecord to {|Root-Nested|:23}
	soml's decode("root-nested:0")
	set made to soml's fromEntries({{"root-nested", originalRecord}})
	set actualPairs to soml's entries(made)
	set actualRecord to item 2 of item 1 of actualPairs
	checkPairs("Root spelling or value association changed", {{item 1 of item 1 of actualPairs, item 2 of item 1 of soml's entries(actualRecord)}}, {{"root-nested", 23}})
	checkPairs("A root label changed a nested case variant", soml's entries(item 2 of item 1 of actualPairs), {{"Root-Nested", 23}})
	checkText("Root and nested case variant output changed", soml's encode(made), "root-nested: {" & linefeed & tab & "Root-Nested: 23" & linefeed & "}" & linefeed)
end testRootNestedCaseInteraction

on testOrdinaryNestedConstruction()
	-- These literal keys have no conflicting registered spelling, including the empty key.
	set originalRecord to {||:3, |plain|:4, |Undisturbed-Capital|:5, |café|:6}
	set made to soml's fromEntries({{"container", originalRecord}})
	set testCount to testCount + 1
	if class of made is not record then
		set end of failures to "Ordinary nested values should retain native construction"
	end if
	set actualRecord to item 2 of item 1 of soml's entries(made)
	checkPairs("Ordinary nested labels or values changed", soml's entries(actualRecord), {{"", 3}, {"plain", 4}, {"Undisturbed-Capital", 5}, {"café", 6}})
	checkText("Ordinary nested canonical output changed", soml's encodeCanonical(actualRecord), "'': 3" & linefeed & "Undisturbed-Capital: 5" & linefeed & "'café': 6" & linefeed & "plain: 4" & linefeed)
end testOrdinaryNestedConstruction

on testNativeNullConstruction()
	-- Null is supported throughout native records and lists, rather than an opaque class constant.
	repeat with nullValue in {missing value, null}
		set made to soml's fromEntries({{"optional", contents of nullValue}, {"nested", {optional:contents of nullValue}}, {"array", {contents of nullValue}}})
		set testCount to testCount + 1
		if class of made is not record then
			set end of failures to "Supported null values changed native construction"
		end if
		checkText("Supported null values changed canonical output", soml's encodeCanonical(made), "array: [" & linefeed & tab & "null" & linefeed & "]" & linefeed & "nested: {" & linefeed & tab & "optional: null" & linefeed & "}" & linefeed & "optional: null" & linefeed)
	end repeat
end testNativeNullConstruction

on run
	set failures to {}
	set testCount to 0
	-- Literal labels retain their original spelling until an Apple event serializes the record.
	set originalRecord to {|Nested-Capital|:123}
	soml's decode("nested-capital:0")
	checkKey(originalRecord, "Nested-Capital", 123)
	set originalText to soml's encode(originalRecord)
	repeat with placement in {"direct", "array", "record"}
		set originalValue to originalRecord
		if contents of placement is "array" then
			set originalValue to {originalRecord}
		else if contents of placement is "record" then
			set originalValue to {nested:originalRecord}
		end if
		set made to soml's fromEntries({{"outer", originalValue}})
		set actualValue to item 2 of item 1 of soml's entries(made)
		if contents of placement is "array" then
			set actualValue to item 1 of actualValue
		else if contents of placement is "record" then
			set actualValue to nested of actualValue
		end if
		checkKey(actualValue, "Nested-Capital", 123)
		set testCount to testCount + 1
		if id of soml's encode(actualValue) is not id of originalText then
			set end of failures to "Changed the nested record output"
		end if
		set testCount to testCount + 1
		if id of soml's encodeCanonical(actualValue) is not id of originalText then
			set end of failures to "Changed the canonical nested record output"
		end if
	end repeat
	-- Key spellings in separate records must remain distinct after construction.
	set lowerRecord to soml's decode("nested-capital:456")
	checkKey(lowerRecord, "nested-capital", 456)
	set made to soml's fromEntries({{"outer", {originalRecord, lowerRecord}}})
	set actualValue to item 2 of item 1 of soml's entries(made)
	checkKey(item 1 of actualValue, "Nested-Capital", 123)
	checkKey(item 2 of actualValue, "nested-capital", 456)
	checkKey(originalRecord, "Nested-Capital", 123)
	testMultipleNestedLabels()
	testRootNestedCaseInteraction()
	testOrdinaryNestedConstruction()
	testNativeNullConstruction()
	if failures is not {} then
		error soml's joinTexts(failures, linefeed)
	end if
	return (testCount as text) & " nested construction spelling checks passed"
end run
