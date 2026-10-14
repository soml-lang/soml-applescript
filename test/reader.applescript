(*
Reader regressions for adversarial keys and collection boundaries.
*)
use AppleScript version "2.8"
use soml : script "SOML"

on run
	set config to soml's decode("{'é': 1, 'e" & character id 769 & "': 2}")
	set pairs to soml's entries(config)
	if (count pairs) is not 2 or soml's codePoints(item 1 of item 1 of pairs) is not {233} or soml's codePoints(item 1 of item 2 of pairs) is not {101, 769} then
		error "Canonically equivalent Unicode keys were merged"
	end if
	set parts to {}
	repeat with step from 1 to 600
		set digits to text -6 thru -1 of ("000000" & step)
		set end of parts to "prefix" & digits & "suffix: " & step
	end repeat
	set theText to soml's joinTexts(parts, linefeed)
	set config to soml's decode(theText)
	set pairs to soml's entries(config)
	if (count pairs) is not 600 or item 2 of item 600 of pairs is not 600 then
		error "Adversarial keys lost values or order"
	end if
	set config to soml's decode(theText & linefeed & "'é': 1" & linefeed & "'e" & character id 769 & "': 2")
	set pairs to soml's entries(config)
	if (count pairs) is not 602 or soml's codePoints(item 1 of item 601 of pairs) is not {233} or soml's codePoints(item 1 of item 602 of pairs) is not {101, 769} then
		error "Native key tracking merged canonically equivalent Unicode keys"
	end if
	set config to soml's decode(theText & linefeed & "PREFIX000600SUFFIX: true")
	if class of config is not SOML object or (count entries of config) is not 601 then
		error "Case collision among distinct keys must keep both entries"
	end if
	try
		soml's decode(theText & linefeed & "prefix000600suffix: true")
		error "Duplicate among adversarial keys was accepted" number 99
	on error message number errorNumber
		if errorNumber is not 1 or message does not contain "Duplicate key prefix000600suffix" then
			error message number errorNumber
		end if
	end try
	set config to soml's decode("leading: [0.5, {nested: true}]" & linefeed & theText & linefeed & "trailing: {value: 1.5}")
	if item 1 of leading of config is not 0.5 or nested of item 2 of leading of config is not true or value of trailing of config is not 1.5 then
		error "Frame restoration lost nested values or pending floats"
	end if
	set parts to {}
	repeat with step from 1 to 4001
		set end of parts to "boundary" & step & ": {shared: " & step & "}"
	end repeat
	set config to soml's decode(soml's joinTexts(parts, linefeed))
	if class of config is not SOML object or (count entries of config) is not 4001 or class of item 2 of item 1 of entries of config is not SOML object then
		error "A document past the distinct-key limit must keep every object tagged"
	end if
	return "7 reader regression checks passed"
end run
