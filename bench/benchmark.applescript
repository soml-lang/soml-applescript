(*
Reads and writes the shared benchmark fixtures with this library, and the same data as JSON with `NSJSONSerialization`, which is how AppleScript reads and writes JSON, through AppleScriptObjC. AppleScript has no TOML library in common use.

	make bench
	make bench FIXTURE=service SAMPLES=5

The fixtures are a copy of the benchmark fixtures in the `soml` repository, which every implementation shares, and its readme describes each of them. The times are per document, the median of several runs, in wall time after an untimed warmup. A writer writes the value that its own reader read. Reading JSON includes making AppleScript records and lists of the result, as a script needs them, and writing JSON starts from them.

Prints a Markdown table.
*)

use AppleScript version "2.8"
use framework "Foundation"
use scripting additions
use soml : script "SOML"

property fixtures : {{"service", 21}, {"platform", 11}, {"earthquakes", 5}}

on run arguments
	set usage to "Usage: osascript bench/benchmark.applescript [all|service|platform|earthquakes] [positive sample count]"
	if (count arguments) > 2 then
		error usage
	end if
	set requestedFixture to "all"
	set requestedSamples to missing value
	if (count arguments) > 0 then
		set requestedFixture to item 1 of arguments
		if requestedFixture = "--help" then
			return usage
		end if
	end if
	if requestedFixture is not in {"all", "service", "platform", "earthquakes"} then
		error usage
	end if
	if (count arguments) > 1 and item 2 of arguments is not "" then
		set sampleText to item 2 of arguments
		try
			set requestedSamples to sampleText as integer
			if requestedSamples < 1 or (requestedSamples as text) is not sampleText then
				error usage
			end if
		on error
			error usage
		end try
	end if
	set fixturesFolder to (POSIX path of ((path to me as text) & "::")) & "fixtures/"
	set rows to {"| | SOML for AppleScript | NSJSONSerialization |", "|---|--:|--:|"}
	set readRows to {}
	set writeRows to {}
	repeat with fixture in fixtures
		set fixtureName to item 1 of fixture
		set sampleCount to item 2 of fixture
		if requestedSamples is not missing value then
			set sampleCount to requestedSamples
		end if
		if requestedFixture = "all" or requestedFixture = fixtureName then
			set somlText to readText(fixturesFolder & fixtureName & ".soml")
			set jsonData to readData(fixturesFolder & fixtureName & ".json")
			set somlRead to median(measureSOMLRead(somlText, sampleCount))
			set somlValue to soml's decode(somlText)
			set somlWrite to median(measureSOMLWrite(somlValue, sampleCount))
			set jsonRead to median(measureJSONRead(jsonData, sampleCount))
			set jsonValue to decodeJSON(jsonData)
			set jsonWrite to median(measureJSONWrite(jsonValue, sampleCount))
			set end of readRows to "| Read `" & fixtureName & "` | " & formatDuration(somlRead) & " | " & formatDuration(jsonRead) & " |"
			set end of writeRows to "| Write `" & fixtureName & "` | " & formatDuration(somlWrite) & " | " & formatDuration(jsonWrite) & " |"
		end if
	end repeat
	return ((current application's NSArray's arrayWithArray:(rows & readRows & writeRows))'s componentsJoinedByString:linefeed) as text
end run

on now()
	return (current application's NSProcessInfo's processInfo()'s systemUptime()) as real
end now

on measureSOMLRead(theText, sampleCount)
	soml's decode(theText)
	script Store
		property durations : {}
	end script
	repeat sampleCount times
		set startTime to now()
		soml's decode(theText)
		set end of Store's durations to now() - startTime
	end repeat
	return Store's durations
end measureSOMLRead

on measureSOMLWrite(theValue, sampleCount)
	soml's encode(theValue)
	script Store
		property durations : {}
	end script
	repeat sampleCount times
		set startTime to now()
		soml's encode(theValue)
		set end of Store's durations to now() - startTime
	end repeat
	return Store's durations
end measureSOMLWrite

on measureJSONRead(theData, sampleCount)
	decodeJSON(theData)
	script Store
		property durations : {}
	end script
	repeat sampleCount times
		set startTime to now()
		decodeJSON(theData)
		set end of Store's durations to now() - startTime
	end repeat
	return Store's durations
end measureJSONRead

on measureJSONWrite(theValue, sampleCount)
	encodeJSON(theValue)
	script Store
		property durations : {}
	end script
	repeat sampleCount times
		set startTime to now()
		encodeJSON(theValue)
		set end of Store's durations to now() - startTime
	end repeat
	return Store's durations
end measureJSONWrite

on decodeJSON(theData)
	set {theObject, jsonError} to current application's NSJSONSerialization's JSONObjectWithData:theData options:0 |error|:(reference)
	if theObject is missing value then
		error "Could not decode benchmark JSON: " & (jsonError's localizedDescription() as text)
	end if
	return item 1 of ((current application's NSArray's arrayWithObject:theObject) as list)
end decodeJSON

on encodeJSON(theValue)
	set {theData, jsonError} to current application's NSJSONSerialization's dataWithJSONObject:theValue options:(current application's NSJSONWritingPrettyPrinted) |error|:(reference)
	if theData is missing value then
		error "Could not encode benchmark JSON: " & (jsonError's localizedDescription() as text)
	end if
	return (current application's NSString's alloc()'s initWithData:theData encoding:(current application's NSUTF8StringEncoding)) as text
end encodeJSON

on readData(thePath)
	set {theData, readError} to current application's NSData's dataWithContentsOfFile:thePath options:0 |error|:(reference)
	if theData is missing value then
		error "Could not read benchmark fixture " & thePath & ": " & (readError's localizedDescription() as text)
	end if
	return theData
end readData

on readText(thePath)
	set theText to current application's NSString's alloc()'s initWithData:(readData(thePath)) encoding:(current application's NSUTF8StringEncoding)
	if theText is missing value then
		error "Benchmark fixture is not UTF-8: " & thePath
	end if
	return theText as text
end readText

on median(theDurations)
	set sampleCount to count theDurations
	if sampleCount = 0 then
		error "Cannot calculate the median of no samples"
	end if
	if sampleCount = 1 then
		return item 1 of theDurations
	end if
	set sorted to ((current application's NSArray's arrayWithArray:theDurations)'s sortedArrayUsingSelector:"compare:") as list
	set middleIndex to sampleCount div 2 + 1
	if sampleCount mod 2 = 0 then
		return ((item (middleIndex - 1) of sorted) + (item middleIndex of sorted)) / 2
	end if
	return item middleIndex of sorted
end median

-- A duration in seconds as the readmes show it, with two or three significant digits: 28 µs, 1.9 ms, 12 ms, 2.4 s.
on formatDuration(theSeconds)
	if theSeconds < 0.001 then
		return roundTo(theSeconds * 1000000) & " µs"
	else if theSeconds < 1 then
		return roundTo(theSeconds * 1000) & " ms"
	end if
	return roundTo(theSeconds) & " s"
end formatDuration

-- Two significant digits below 10, and whole numbers above, written without the locale.
on roundTo(theNumber)
	if theNumber < 10 then
		set tenths to (round (theNumber * 10)) as integer
		return ((tenths div 10) as text) & "." & ((tenths mod 10) as text)
	end if
	return ((round theNumber) as integer) as text
end roundTo
