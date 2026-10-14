(*
Native calendar dates preserve exact Gregorian components and remain distinct from strings, instants, and AppleScript dates.
*)
use AppleScript version "2.8"
use scripting additions
use soml : script "SOML"

on run
	set checks to 0
	repeat with dateText in {"0001-01-01", "0099-01-01", "9999-12-31", "1582-10-10", "2011-12-30", "2000-02-29", "2026-11-01"}
		set dateText to contents of dateText
		set values to soml's decode("[" & dateText & ", '" & dateText & "']")
		set theDate to item 1 of values
		if class of theDate is not «class SOMc» or value of theDate is not dateText then
			error "Date components or native class changed: " & dateText
		end if
		if class of item 2 of values is not text then
			error "Quoted date was inferred as a native date"
		end if
		set canonical to "[" & linefeed & tab & dateText & linefeed & tab & "'" & dateText & "'" & linefeed & "]" & linefeed
		if soml's encodeCanonical(values) is not canonical then
			error "Date canonical output changed: " & dateText
		end if
		if soml's encodeCanonical(soml's decode(canonical)) is not canonical then
			error "Date round trip changed: " & dateText
		end if
		set constructed to {class:«class SOMc», value:dateText}
		if soml's encodeCanonical({constructed}) is not "[" & linefeed & tab & dateText & linefeed & "]" & linefeed then
			error "A native tagged date did not encode"
		end if
		set checks to checks + 5
	end repeat
	repeat with token in {"1900-02-29", "2100-02-29", "2026-02-30", "0000-01-01", "10000-01-01", "2026-1-01", "2026-01-1", "2026-13-01", "2026-01-00", "2026-11-01T", "2026-11-01Z", "2026-11-01foo", "2026-11-01T12:00:00", "２０２６-11-01"}
		set token to contents of token
		try
			soml's decode("[" & token & "]")
			error "Accepted invalid date: " & token
		on error number 1
			set checks to checks + 1
		end try
		try
			set invalidDate to {class:«class SOMc», value:token}
			soml's encode({invalidDate})
			error "Encoded invalid native date: " & token
		on error number 2
			set checks to checks + 1
		end try
	end repeat
	set theDate to item 1 of soml's decode("[2026-11-01]")
	try
		soml's toDate(theDate)
		error "A calendar date converted to an AppleScript instant"
	on error number -1703
		set checks to checks + 1
	end try
	set recordValue to soml's decode("launch:1582-10-10# keep" & linefeed & "next:2011-12-30")
	if class of |launch| of recordValue is not «class SOMc» or class of |next| of recordValue is not «class SOMc» then
		error "Dates changed type across adjacent lines"
	end if
	set checks to checks + 1
	set built to soml's fromEntries({{"launch-date", theDate}, {"2026-11-01", "2026-11-01"}})
	set pairs to soml's entries(built)
	if class of item 2 of item 1 of pairs is not «class SOMc» or class of item 2 of item 2 of pairs is not text then
		error "Native dates changed type through record construction"
	end if
	set checks to checks + 1
	set dateReference to a reference to item 1 of soml's decode("[1582-10-10]")
	if soml's encodeCanonical({contents of dateReference}) is not "[" & linefeed & tab & "1582-10-10" & linefeed & "]" & linefeed then
		error "A referenced date did not encode"
	end if
	set checks to checks + 1
	repeat with malformed in {{class:«class SOMc», value:1}, {class:«class SOMc», value:{"2026-11-01"}}, {class:«class SOMc», other:"2026-11-01"}, {class:«class SOMc», value:"2026-11-01", extra:true}, {class:«class SOMc», value:""}, {class:«class SOMc», value:"2026-11-01 "}, {class:«class SOMc», value:"2026-11-01" & linefeed}}
		try
			soml's encode({contents of malformed})
			error "Encoded a malformed native date record"
		on error number 2
			set checks to checks + 1
		end try
	end repeat
	repeat with dateToken in {"2000-02-29", "1582-10-10", "2011-12-30"}
		set dateToken to contents of dateToken
		set tokens to {dateToken & ",", dateToken & "# comment" & linefeed, dateToken & "/* comment */"}
		repeat with boundaryToken in tokens
			set parsed to soml's decode("[" & contents of boundaryToken & "]")
			if class of item 1 of parsed is not «class SOMc» or value of item 1 of parsed is not dateToken then
				error "A date token boundary changed its value"
			end if
			set checks to checks + 1
		end repeat
	end repeat
	set decoded to soml's decode("[2026-11-01, 2026-11-01T12:00:00Z, '2026-11-01']")
	if class of item 1 of decoded is not «class SOMc» or class of item 2 of decoded is not «class SOMt» or class of item 3 of decoded is not text then
		error "Date, instant, and string types were conflated"
	end if
	set checks to checks + 1
	return (checks as text) & " calendar date checks passed"
end run
