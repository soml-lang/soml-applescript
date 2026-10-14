(*
Native labels resembling class metadata must keep their meaning under the caller's text comparison settings.
*)
use AppleScript version "2.8"
use scripting additions
use soml : script "SOML"
property failures : {}
property testCount : 0

on testLabels(contextName)
	repeat with labelText in {"cl_ass", "c_l_a_s_s", "class_", "_class", "__class__"}
		set labelText to contents of labelText
		set nativeRecord to run script "return {" & labelText & ":7, zeta:9}"
		set expectedText to labelText & ": 7" & linefeed & "zeta: 9" & linefeed
		set testCount to testCount + 1
		try
			set pairs to soml's entries(nativeRecord)
			if (count pairs) is not 2 or id of item 1 of item 1 of pairs is not id of labelText or item 2 of item 1 of pairs is not 7 or id of item 1 of item 2 of pairs is not id of "zeta" or item 2 of item 2 of pairs is not 9 then
				error "Entry spelling or association changed"
			end if
			if id of soml's encode(nativeRecord) is not id of expectedText or id of soml's encodeCanonical(nativeRecord) is not id of expectedText then
				error "Native record output changed"
			end if
		on error message number errorNumber
			set end of failures to contextName & " " & labelText & ": " & errorNumber & " " & message
		end try
		set testCount to testCount + 1
		try
			set expectedNested to "holder: {" & linefeed & tab & labelText & ": 7" & linefeed & tab & "zeta: 9" & linefeed & "}" & linefeed
			if id of soml's encode({holder:nativeRecord}) is not id of expectedNested or id of soml's encodeCanonical({holder:nativeRecord}) is not id of expectedNested then
				error "Nested record output changed"
			end if
		on error message number errorNumber
			set end of failures to contextName & " nested " & labelText & ": " & errorNumber & " " & message
		end try
	end repeat
	-- Real metadata must still be recognized, with any supported field order.
	repeat with theCase in {{{class:SOML int, value:"0xFF"}, "255"}, {{value:"1.50h", class:SOML duration}, "1h30m"}, {{class:SOML instant, value:"2026-09-19T14:00:00+02:00"}, "2026-09-19T12:00:00Z"}}
		set testCount to testCount + 1
		try
			set expectedText to "[" & linefeed & tab & item 2 of theCase & linefeed & "]" & linefeed
			if id of soml's encode({item 1 of theCase}) is not id of expectedText or id of soml's encodeCanonical({item 1 of theCase}) is not id of expectedText then
				error "Tagged scalar metadata was not recognized"
			end if
		on error message number errorNumber
			set end of failures to contextName & " tagged scalar: " & errorNumber & " " & message
		end try
	end repeat
	set testCount to testCount + 1
	try
		set taggedObject to {entries:{{"class", 7}}, class:SOML object}
		if id of soml's encode(taggedObject) is not id of ("class: 7" & linefeed) or id of soml's encodeCanonical(taggedObject) is not id of ("class: 7" & linefeed) or soml's entries(taggedObject) is not {{"class", 7}} then
			error "Tagged object metadata was not recognized"
		end if
	on error message number errorNumber
		set end of failures to contextName & " tagged object: " & errorNumber & " " & message
	end try
end testLabels

on run
	set failures to {}
	set testCount to 0
	considering case, diacriticals, hyphens, punctuation and white space
		testLabels("considering")
	end considering
	ignoring case, diacriticals, hyphens, punctuation and white space
		testLabels("ignoring")
	end ignoring
	if failures is not {} then
		error soml's joinTexts(failures, linefeed)
	end if
	return (testCount as text) & " caller comparison checks passed"
end run
