(*
Native dates and reals use independent field and output expectations. Run with an actual process timezone: TZ=UTC osascript test/native-scalars.applescript UTC, or TZ=America/New_York osascript test/native-scalars.applescript America/New_York.
*)
use AppleScript version "2.8"
use framework "Foundation"
use framework "JavaScriptCore"
use scripting additions
use soml : script "SOML"
property failures : {}
property testCount : 0

on checkDateOutput(theName, nativeDate, instantText)
	set expectedText to "[" & linefeed & tab & instantText & linefeed & "]" & linefeed
	if class of nativeDate is not date or id of soml's encode({nativeDate}) is not id of expectedText or id of soml's encodeCanonical({nativeDate}) is not id of expectedText then
		set end of failures to theName & ": changed native date or instant output"
	end if
end checkDateOutput

on testCalendarFields(theCases)
	repeat with theCase in theCases
		set {instantText, expectedYear, expectedMonth, expectedDay, expectedTime} to contents of theCase
		set testCount to testCount + 1
		try
			set nativeDate to soml's toDate({class:SOML instant, value:instantText})
			if year of nativeDate is not expectedYear or month of nativeDate is not expectedMonth or day of nativeDate is not expectedDay or time of nativeDate is not expectedTime then
				set end of failures to instantText & ": changed local Gregorian calendar fields"
			end if
			checkDateOutput(instantText, nativeDate, instantText)
		on error message number errorNumber
			set end of failures to instantText & ": " & errorNumber & " " & message
		end try
	end repeat
end testCalendarFields

on testFractionalNativeDates()
	-- NSDate can hold fractions; its AppleScript date coercion keeps whole seconds, including before the epoch.
	repeat with theCase in {{-1.9, "1969-12-31T23:59:58Z"}, {-0.1, "1969-12-31T23:59:59Z"}, {0.9, "1970-01-01T00:00:00Z"}, {1.9, "1970-01-01T00:00:01Z"}, {86399.9, "1970-01-01T23:59:59Z"}}
		set {epochSeconds, instantText} to contents of theCase
		set testCount to testCount + 1
		try
			set nativeDate to (current application's NSDate's dateWithTimeIntervalSince1970:epochSeconds) as date
			checkDateOutput("Native fractional date " & epochSeconds, nativeDate, instantText)
		on error message number errorNumber
			set end of failures to "Native fractional date " & epochSeconds & ": " & errorNumber & " " & message
		end try
	end repeat
end testFractionalNativeDates

on testNativeReals()
	set context to current application's JSContext's new()
	-- These are native reals, created independently of the SOML decoder.
	repeat with theCase in {{"Infinity", "infinity"}, {"-Infinity", "-infinity"}, {"-0", "0.0"}, {"Number.MIN_VALUE", "5e-324"}, {"Number.MAX_VALUE", "1.7976931348623157e308"}, {"NaN", missing value}}
		set {expression, expectedNumberText} to contents of theCase
		set testCount to testCount + 1
		try
			set nativeReal to ((context's evaluateScript:expression)'s toDouble()) as real
			if class of nativeReal is not real then
				error "Fixture did not produce a native real"
			end if
			if expectedNumberText is missing value then
				repeat with canonicalMode in {false, true}
					try
						if canonicalMode then
							soml's encodeCanonical({nested:{value:nativeReal}})
						else
							soml's encode({nested:{value:nativeReal}})
						end if
						set end of failures to "Native NaN was accepted"
					on error message number errorNumber
						if errorNumber is not 2 or message does not contain "nested.value" then
							set end of failures to "Native NaN: changed error number or path"
						end if
					end try
				end repeat
			else
				set expectedText to "nested: {" & linefeed & tab & "value: " & expectedNumberText & linefeed & "}" & linefeed
				if id of soml's encode({nested:{value:nativeReal}}) is not id of expectedText or id of soml's encodeCanonical({nested:{value:nativeReal}}) is not id of expectedText then
					set end of failures to expression & ": changed native real output"
				end if
			end if
		on error message number errorNumber
			set end of failures to expression & ": " & errorNumber & " " & message
		end try
	end repeat
end testNativeReals

on run {timezoneName}
	set failures to {}
	set testCount to 0
	if timezoneName is "UTC" then
		-- Explicit fields verify the proleptic Gregorian calendar independently of an encoder round trip.
		testCalendarFields({{"0001-01-01T00:00:00Z", 1, January, 1, 0}, {"0099-12-31T23:59:59Z", 99, December, 31, 86399}, {"0100-03-01T00:00:00Z", 100, March, 1, 0}, {"0400-02-29T23:59:59Z", 400, February, 29, 86399}, {"1500-03-01T00:00:00Z", 1500, March, 1, 0}, {"1582-10-04T12:00:00Z", 1582, October, 4, 43200}, {"1582-10-10T12:00:00Z", 1582, October, 10, 43200}, {"1582-10-15T12:00:00Z", 1582, October, 15, 43200}, {"1900-03-01T00:00:00Z", 1900, March, 1, 0}, {"2000-02-29T23:59:59Z", 2000, February, 29, 86399}, {"9999-12-31T23:59:59Z", 9999, December, 31, 86399}})
		testFractionalNativeDates()
		testNativeReals()
	else if timezoneName is "America/New_York" then
		-- A valid UTC instant can have local year 0; the UTC range applies to the instant, not its local calendar fields.
		set testCount to testCount + 1
		try
			set nativeDate to soml's toDate({class:SOML instant, value:"0001-01-01T00:00:00Z"})
			if year of nativeDate is not 0 then
				set end of failures to "Minimum UTC instant changed its local year"
			end if
			checkDateOutput("Minimum UTC instant in New York", nativeDate, "0001-01-01T00:00:00Z")
		on error message number errorNumber
			set end of failures to "Minimum UTC instant in New York: " & errorNumber & " " & message
		end try
		-- Spring's skipped hour is unambiguous; the documented repeated autumn hour is excluded.
		testCalendarFields({{"1970-01-01T00:00:00Z", 1969, December, 31, 68400}, {"2024-03-10T06:59:59Z", 2024, March, 10, 7199}, {"2024-03-10T07:00:00Z", 2024, March, 10, 10800}, {"2024-07-01T12:00:00Z", 2024, July, 1, 28800}})
	else
		error "Run with the matching UTC or America/New_York process timezone and argument"
	end if
	if failures is not {} then
		error soml's joinTexts(failures, linefeed)
	end if
	return (testCount as text) & " native scalar checks passed in " & timezoneName
end run
