(*
Repeated encoder calls must not break exact integer conversion.

	make helper-state
*)
use AppleScript version "2.8"
use scripting additions
use soml : script "SOML"
set expectedText to "[" & linefeed & tab & "5566210968827310" & linefeed & "]" & linefeed
set tagged to {class:SOML int, value:"0x13_C67_07B_8AB_5AE"}
repeat 1000 times
	if id of soml's encodeCanonical({tagged}) is not id of expectedText then
		error "Wrong encoding"
	end if
	if soml's toNumber(tagged) is not 5566210968827310.0 then
		error "Wrong exact number"
	end if
end repeat
return "1 repeated integer helper regression passed"
