(*
Public handlers resolve ordinary root references without changing direct values or flattening surrounding containers. References stored inside data remain unsupported.
*)
use AppleScript version "2.8"
use framework "Foundation"
use scripting additions
use soml : script "SOML"
property failures : {}
property checks : 0
on checkText(theName, actual, expected)
	set checks to checks + 1
	if id of actual is not id of expected then
		set end of failures to theName & ": wrong exact text"
	end if
end checkText
set ordinaryRecord to {z:1, a:0.125}
set nativeList to {1, 0.125, "x"}
set taggedObject to {class:SOML object, entries:{{"Z", 2}, {"A", 3}}}
set rootValues to {ordinaryRecord, nativeList, taggedObject}
set expectedNormals to {"z: 1" & linefeed & "a: 0.125" & linefeed, "[" & linefeed & tab & "1" & linefeed & tab & "0.125" & linefeed & tab & "'x'" & linefeed & "]" & linefeed, "Z: 2" & linefeed & "A: 3" & linefeed}
set expectedCanonicals to {"a: 0.125" & linefeed & "z: 1" & linefeed, item 2 of expectedNormals, "A: 3" & linefeed & "Z: 2" & linefeed}
set expectedEntries to {{{"z", 1}, {"a", 0.125}}, {}, {{"Z", 2}, {"A", 3}}}
set step to 0
repeat with rootValue in rootValues
	set step to step + 1
	try
		checkText("loop root normal " & step, soml's encode(rootValue), item step of expectedNormals)
	on error message number errorNumber
		set end of failures to "loop root normal " & step & ": " & errorNumber & " " & message
	end try
	try
		checkText("loop root canonical " & step, soml's encodeCanonical(rootValue), item step of expectedCanonicals)
	on error message number errorNumber
		set end of failures to "loop root canonical " & step & ": " & errorNumber & " " & message
	end try
	if step is not 2 then
		try
			set checks to checks + 1
			if soml's entries(rootValue) is not item step of expectedEntries then
				set end of failures to "loop root entries " & step & ": changed key/value pairs"
			end if
		on error message number errorNumber
			set end of failures to "loop root entries " & step & ": " & errorNumber & " " & message
		end try
	end if
end repeat
set collectionsOfPairs to {{{"z", 1}, {"a", 0.125}}, {{"Z", 2}, {"A", 3}}}
set step to 0
repeat with rootPairs in collectionsOfPairs
	set step to step + 1
	try
		set expectedText to item 1 of expectedNormals
		if step is 2 then
			set expectedText to item 3 of expectedNormals
		end if
		checkText("loop root fromEntries " & step, soml's encode(soml's fromEntries(rootPairs)), expectedText)
	on error message number errorNumber
		set end of failures to "loop root fromEntries " & step & ": " & errorNumber & " " & message
	end try
end repeat
-- A naive contents-of operation must not replace an ordinary record with this label's value.
set keywordRecord to {contents:"kept", properties:{x:1}, |class|:"data", other:7}
set keywordExpected to "contents: 'kept'" & linefeed & "properties: {" & linefeed & tab & "x: 1" & linefeed & "}" & linefeed & "class: 'data'" & linefeed & "other: 7" & linefeed
try
	checkText("direct keyword record", soml's encode(keywordRecord), keywordExpected)
	set keywordRoots to {keywordRecord}
	repeat with keywordRoot in keywordRoots
		checkText("referenced keyword record", soml's encode(keywordRoot), keywordExpected)
	end repeat
on error message number errorNumber
	set end of failures to "keyword record: " & errorNumber & " " & message
end try
-- The public integer helper must return a number, rather than passing its loop reference through.
set wideInteger to 536870911 + 1
set nativeIntegers to {255, wideInteger}
set integerTexts to {"255", "536870912"}
set step to 0
repeat with nativeInteger in nativeIntegers
	set step to step + 1
	try
		set resultNumber to soml's toNumber(nativeInteger)
		if class of resultNumber is not integer or resultNumber is not item step of nativeIntegers then
			set end of failures to "native integer root " & step & ": changed class or value"
		end if
		checkText("native integer result " & step, soml's encode({resultNumber}), "[" & linefeed & tab & item step of integerTexts & linefeed & "]" & linefeed)
	on error message number errorNumber
		set end of failures to "native integer root " & step & ": " & errorNumber & " " & message
	end try
end repeat
-- A numeric helper result is a snapshot of an immutable integer, not a live reference to the caller's list.
set snapshotSource to {255}
repeat with currentInteger in snapshotSource
	try
		set integerSnapshot to soml's toNumber(currentInteger)
		set item 1 of snapshotSource to 511
		set checks to checks + 1
		if class of integerSnapshot is not integer or integerSnapshot is not 255 then
			set end of failures to "Integer helper result changed after source mutation"
		end if
	on error message number errorNumber
		set end of failures to "Integer helper snapshot: " & errorNumber & " " & message
	end try
end repeat
-- Text and tagged scalar roots already work, and must keep their results when normalized uniformly.
repeat with sourceText in {"z: 1"}
	try
		checkText("text root decode", soml's encode(soml's decode(sourceText)), "z: 1" & linefeed)
	on error message number errorNumber
		set end of failures to "text root decode: " & errorNumber & " " & message
	end try
end repeat
repeat with taggedInteger in {{class:SOML int, value:"0xFF"}}
	try
		checkText("tagged integer root", soml's encode({soml's toNumber(taggedInteger)}), "[" & linefeed & tab & "255" & linefeed & "]" & linefeed)
	on error message number errorNumber
		set end of failures to "tagged integer root: " & errorNumber & " " & message
	end try
end repeat
repeat with taggedDuration in {{value:"1.50h", class:SOML duration}}
	try
		checkText("duration root", soml's encode({soml's toSeconds(taggedDuration)}), "[" & linefeed & tab & "5400.0" & linefeed & "]" & linefeed)
	on error message number errorNumber
		set end of failures to "duration root: " & errorNumber & " " & message
	end try
end repeat
repeat with taggedInstant in {{value:"2026-09-19T14:00:00+02:00", class:SOML instant}}
	try
		checkText("instant root", soml's encode({soml's toDate(taggedInstant)}), "[" & linefeed & tab & "2026-09-19T12:00:00Z" & linefeed & "]" & linefeed)
	on error message number errorNumber
		set end of failures to "instant root: " & errorNumber & " " & message
	end try
end repeat
-- File arguments use a real UTF-8 fixture and actual path, file and alias loop references.
set fixturePath to (POSIX path of (path to temporary items)) & "soml-applescript-root-reference-" & ((current application's NSUUID's UUID()'s UUIDString()) as text) & ".soml"
set fixtureWritten to (current application's NSString's stringWithString:"z: 1")'s writeToFile:fixturePath atomically:true encoding:(current application's NSUTF8StringEncoding) |error|:(missing value)
if not fixtureWritten then
	error "Could not create the reference file fixture"
end if
set fixtureFile to POSIX file fixturePath
set fixtureAlias to fixtureFile as alias
set fileArguments to {fixturePath, fixtureFile, fixtureAlias}
set step to 0
repeat with fileArgument in fileArguments
	set step to step + 1
	try
		checkText("file root " & step, soml's encode(soml's decodeFile(fileArgument)), "z: 1" & linefeed)
	on error message number errorNumber
		set end of failures to "file root " & step & ": " & errorNumber & " " & message
	end try
end repeat
-- Ordinary direct values, including opaque physical records, must not be coerced through their contents fields.
script opaqueScript
	property contents : "script contents"
end script
set nativeDate to soml's toDate({class:SOML instant, value:"2026-09-19T12:00:00Z"})
set ordinaryValues to {"", "text", 1, wideInteger, 0.125, true, nativeDate, missing value, null, opaqueScript, keywordRecord, {class:SOML int, value:"0xFF"}}
repeat with step from 1 to count ordinaryValues
	try
		set originalValue to item step of ordinaryValues
		set resultObject to soml's fromEntries({{"kept", originalValue}})
		set actualValue to item 2 of item 1 of soml's entries(resultObject)
		set checks to checks + 1
		if class of actualValue is not class of originalValue or actualValue is not originalValue then
			set end of failures to "direct native value " & step & ": changed class or value"
		end if
	on error message number errorNumber
		set end of failures to "direct native value " & step & ": " & errorNumber & " " & message
	end try
end repeat
repeat with metadataClass in {text, record, reference}
	try
		set metadataClass to contents of metadataClass
		set opaqueRecord to {class:metadataClass, contents:"opaque contents", other:123}
		set resultObject to soml's fromEntries({{"kept", opaqueRecord}})
		set actualValue to item 2 of item 1 of soml's entries(resultObject)
		set checks to checks + 1
		if class of actualValue is not metadataClass or (actualValue as record as list) is not {metadataClass, "opaque contents", 123} then
			set end of failures to "direct opaque record: changed class or physical fields"
		end if
	on error message number errorNumber
		set end of failures to "direct opaque record: " & errorNumber & " " & message
	end try
end repeat
-- A contents label is data, and must not make an argument of the wrong type appear valid.
repeat with handlerName in {"decode", "decodeFile", "toNumber", "toDate", "toSeconds"}
	set checks to checks + 1
	try
		if contents of handlerName is "decode" then
			soml's decode({contents:"z: 1"})
		else if contents of handlerName is "decodeFile" then
			soml's decodeFile({contents:fixturePath})
		else if contents of handlerName is "toNumber" then
			soml's toNumber({contents:255})
		else if contents of handlerName is "toDate" then
			soml's toDate({contents:{class:SOML instant, value:"2026-09-19T12:00:00Z"}})
		else
			soml's toSeconds({contents:{class:SOML duration, value:"1h"}})
		end if
		set end of failures to "Wrong-type contents record was accepted by " & handlerName
	on error message number errorNumber
		if errorNumber is not -1703 then
			set end of failures to "Wrong-type contents record: " & errorNumber & " " & message
		end if
	end try
end repeat
-- Genuine singleton containers retain every array level, including native dates coercible to references.
set simpleRecord to {child:7}
set simpleTaggedObject to {class:SOML object, entries:{{"K", 7}}}
set singletonDateText to "[" & linefeed & tab & "2026-09-19T12:00:00Z" & linefeed & "]" & linefeed
set nestedDateText to "[" & linefeed & tab & "[" & linefeed & tab & tab & "2026-09-19T12:00:00Z" & linefeed & tab & "]" & linefeed & "]" & linefeed
set singletonRecordText to "[" & linefeed & tab & "{" & linefeed & tab & tab & "child: 7" & linefeed & tab & "}" & linefeed & "]" & linefeed
set nestedRecordText to "[" & linefeed & tab & "[" & linefeed & tab & tab & "{" & linefeed & tab & tab & tab & "child: 7" & linefeed & tab & tab & "}" & linefeed & tab & "]" & linefeed & "]" & linefeed
set singletonObjectText to "[" & linefeed & tab & "{" & linefeed & tab & tab & "K: 7" & linefeed & tab & "}" & linefeed & "]" & linefeed
set nestedObjectText to "[" & linefeed & tab & "[" & linefeed & tab & tab & "{" & linefeed & tab & tab & tab & "K: 7" & linefeed & tab & tab & "}" & linefeed & tab & "]" & linefeed & "]" & linefeed
set singletonCases to {{{nativeDate}, singletonDateText}, {{{nativeDate}}, nestedDateText}, {{simpleRecord}, singletonRecordText}, {{{simpleRecord}}, nestedRecordText}, {{simpleTaggedObject}, singletonObjectText}, {{{simpleTaggedObject}}, nestedObjectText}}
set step to 0
repeat with singletonCase in singletonCases
	set step to step + 1
	set fixtureCase to contents of singletonCase
	set directValue to item 1 of fixtureCase
	set expectedText to item 2 of fixtureCase
	set stageName to "direct normal"
	try
		checkText("direct singleton normal " & step, soml's encode(directValue), expectedText)
		set stageName to "direct canonical"
		checkText("direct singleton canonical " & step, soml's encodeCanonical(directValue), expectedText)
		repeat with listRoot in {directValue}
			set stageName to "reference normal"
			checkText("referenced singleton normal " & step, soml's encode(listRoot), expectedText)
			set stageName to "reference canonical"
			checkText("referenced singleton canonical " & step, soml's encodeCanonical(listRoot), expectedText)
		end repeat
	on error message number errorNumber
		set end of failures to "singleton container " & step & " " & stageName & ": " & errorNumber & " " & message
	end try
end repeat
-- Stored references are outside this contract. Normalizing the root must never unwrap their surrounding list.
set listSources to {{1, 2}}
set listReference to a reference to item 1 of listSources
set unsupportedWrapper to {listReference}
repeat with canonicalMode in {false, true}
	set checks to checks + 1
	try
		if canonicalMode then
			soml's encodeCanonical(unsupportedWrapper)
		else
			soml's encode(unsupportedWrapper)
		end if
		set end of failures to "A stored reference was unwrapped and accepted"
	on error
		-- The stored reference remains unsupported; the root resolver must not turn it into a different valid document.
	end try
end repeat
-- Opaque records with class:list must stay physical records inside their original containers.
set opaqueListRecord to {class:list, contents:"opaque contents", other:123}
set opaqueContainer to {opaqueListRecord}
set checks to checks + 1
try
	soml's encode(opaqueContainer)
	set end of failures to "Opaque list record was accepted"
on error message number errorNumber
	if errorNumber is not 2 or message does not contain "[0]" then
		set end of failures to "Opaque singleton rejection changed: " & errorNumber & " " & message
	end if
end try
try
	set resultObject to soml's fromEntries({{"kept", opaqueContainer}})
	set actualContainer to item 2 of item 1 of soml's entries(resultObject)
	set checks to checks + 1
	if class of actualContainer is not list or (count actualContainer) is not 1 or ((item 1 of actualContainer) as record as list) is not {list, "opaque contents", 123} then
		set end of failures to "Opaque singleton builder value changed"
	end if
on error message number errorNumber
	set end of failures to "Opaque singleton builder: " & errorNumber & " " & message
end try
(current application's NSFileManager's defaultManager())'s removeItemAtPath:fixturePath |error|:(missing value)
if failures is not {} then
	error soml's joinTexts(failures, linefeed)
end if
return (checks as text) & " root reference checks passed"
