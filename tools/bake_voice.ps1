#requires -Version 5.1
<#
.SYNOPSIS
Bakes LaZer NFC's original spoken prompts with installed, offline System.Speech.
.DESCRIPTION
Run with Windows PowerShell:
  powershell.exe -NoProfile -File tools\bake_voice.ps1
  powershell.exe -NoProfile -File tools\bake_voice.ps1 -Check

These are Microsoft Zira Desktop text-to-speech WAVs, not human/source
recordings and not a custom-trained voice. All prompt text is defined below.
No web service, external recording, downloaded voice or runtime TTS is needed
by the game. The checked-in files are the portable playback product.

The same installed voice and Windows speech-engine version reproduce the
speech; different engines/voices can produce different PCM. Python's stdlib
bake_colors.py trims silence and normalizes mono PCM16/44100 Hz with headroom.
Short, faster numbered-round takes fit the model's announcement gap.
.PARAMETER Check
Re-render to a private temporary directory and compare final WAV bytes without
changing the checked-in bank.
#>
[CmdletBinding()]
param(
	[string]$Voice = "Microsoft Zira Desktop",
	[ValidateRange(-10, 10)][int]$Rate = 3,
	[ValidateRange(-10, 10)][int]$RoundRate = 6,
	[string]$Python = "python",
	[switch]$Check
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Speech
$gameRoot = Split-Path -Parent $PSScriptRoot
$destination = Join-Path $gameRoot "assets\audio\voice"
$baker = Join-Path $PSScriptRoot "bake_colors.py"
$temporary = Join-Path ([System.IO.Path]::GetTempPath()) (
	"lazer-nfc-voice-" + [Guid]::NewGuid().ToString("N")
)
$synth = [System.Speech.Synthesis.SpeechSynthesizer]::new()

try {
	$installed = @($synth.GetInstalledVoices() | Where-Object {
		$_.Enabled -and $_.VoiceInfo.Name -eq $Voice
	})
	if ($installed.Count -ne 1) {
		throw "The requested offline voice '$Voice' is not installed and enabled."
	}
	$synth.SelectVoice($Voice)
	$synth.Volume = 100
	$format = [System.Speech.AudioFormat.SpeechAudioFormatInfo]::new(
		44100,
		[System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen,
		[System.Speech.AudioFormat.AudioChannel]::Mono
	)
	$prompts = [ordered]@{
		ready = "Ready. Tap a tag to start."
		recall = "Recall!"
		round = "Round."
		score = "Score."
		round_won = "Round cleared!"
		clean_wave = "Clean sweep!"
		run_over = "Experiment complete."
		assisted = "Assisted."
		binding = "Tag roll call. Tap your phone's upper back against each tag."
		need_tags = "Bind three colours, or choose keys and touch."
		bound = "Bound."
		skipped = "Skipped."
		shades_on = "Shades on."
		shades_off = "Shades off."
		touch_on = "Touch pad shown."
		touch_off = "Touch pad hidden."
		settings_changed = "Settings changed."
		nfc_off = "N. F. C. unavailable. Keys and touch are ready."
		not_yet = "Not yet."
		unknown = "Unknown tag."
		practice = "Learn the sounds."
		gestures = "Double tap red for shades, yellow for the touch pad, or violet to bind tags again."
	}
	$numbers = @(
		"zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
		"ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen",
		"seventeen", "eighteen", "nineteen", "twenty"
	)
	for ($i = 0; $i -lt $numbers.Count; $i++) {
		$prompts["number_$i"] = $numbers[$i] + "."
	}
	$tens = @("thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety")
	for ($i = 0; $i -lt $tens.Count; $i++) {
		$prompts["number_" + (($i + 3) * 10)] = $tens[$i] + "."
	}
	$prompts["number_100"] = "Hundred."
	$prompts["number_1000"] = "Thousand."
	for ($i = 1; $i -le 20; $i++) {
		$prompts["round_$i"] = "Round " + $numbers[$i] + "."
	}
	foreach ($hue in @("red", "orange", "yellow", "green", "blue", "indigo", "violet")) {
		foreach ($shade in @("base", "dark", "light")) {
			$key = if ($shade -eq "base") { $hue } else { "${hue}_$shade" }
			$text = if ($shade -eq "base") { $hue } else { "$shade $hue" }
			$prompts[$key] = $text + "."
			$prompts["bind_$key"] = "Scan the tag for $text."
		}
	}

	New-Item -ItemType Directory -Path $temporary | Out-Null
	foreach ($entry in $prompts.GetEnumerator()) {
		$synth.Rate = if ($entry.Key -match "^round_\d+$") {
			$RoundRate
		} elseif ($entry.Key -match "^number_") {
			[Math]::Min($Rate + 2, 10)
		} else {
			$Rate
		}
		$path = Join-Path $temporary ($entry.Key + ".wav")
		$synth.SetOutputToWaveFile($path, $format)
		$synth.Speak($entry.Value)
		$synth.SetOutputToNull()
	}
	$arguments = @($baker, "--voice-source", $temporary, "--voice-destination", $destination)
	if ($Check) {
		$arguments += "--check"
	}
	& $Python @arguments
	if ($LASTEXITCODE -ne 0) {
		throw "Offline voice finishing failed with exit code $LASTEXITCODE."
	}
	Write-Output ("Voice authoring: {0}; System.Speech; core rate {1}, round rate {2}." -f
		$Voice, $Rate, $RoundRate)
} finally {
	$synth.Dispose()
	if (Test-Path -LiteralPath $temporary) {
		Get-ChildItem -LiteralPath $temporary -File -Filter "*.wav" | ForEach-Object {
			Remove-Item -LiteralPath $_.FullName
		}
		Remove-Item -LiteralPath $temporary
	}
}
