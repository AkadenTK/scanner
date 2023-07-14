# Scanner

This addon scans for a target by name or index, and then can enable tracking for a found target.

Special thanks to: 
https://github.com/Darkdoom22/Widescan

## Features

### Scanning
Uses widescan to alert the user that a desired target is nearby. If a sound effect is configured (on by default), then a sound effect will play when a target is found.

### Auto-scan
Uses widescan in a set interval (with a random wiggle option available). If a sound effect is configured (on by default), then a sound effect will play when a target is found.

Auto-scan works on a delay-and-wiggle system, where a base delay is modified with a random value between `delay + wiggle` and `delay - wiggle`. This lowers the chances that the server will flag frequent widescans for being robotic.

### Tracking
When scanning with tracking enabled, the closest found target will automatically be tracked via the in-game widescan tracking feature. While tracking, auto-scanning is disabled. After tracking is ended (via target death or by manual removal), an optional sleep period will play out. This sleep period can be configured.

## Commands
 Command | Action |
| --- | --- |
| `//scanner stop`  | Cancels any autoscan and tracked targets |
| `//scanner autoscan ...`  | Periodically performs a widescan searching for targets by name or id, separated by spaces (spaces in target names are ignored). Upon finding a target, alerts the user with a message and sound effect. |
| `//scanner autotrack ...`  | Periodically performs a widescan searching for targets by name or id, separated by spaces (spaces in target names are ignored). Upon finding a target, alerts the user with a message and sound effect and then enables tracking on the nearest target. |
| `//scanner scan ...`  | Performs one widescan searching for targets by name or id, separated by spaces (spaces in target names are ignored). Upon finding a target, alerts the user with a message and sound effect. |
| `//scanner track ...`  | Performs one widescan searching for targets by name or id, separated by spaces (spaces in target names are ignored). Upon finding a target, alerts the user with a message and sound effect and then enables tracking on the nearest target. |
| `//scanner set delay #`  | Change the auto-scan base delay (seconds) to a positive integer. |
| `//scanner set wiggle #`  | Change the auto-scan random wiggle value (seconds) to a positive integer. |
| `//scanner set sleep #`  | Change the sleep period (seconds) after a tracked target is lost (by death or manual cancellation) before a new auto-scan can begin. |
| `//scanner set sound [effect_name]`  | Change the sound effect that plays when a target is found in a widescan. Leave `effect_name` empty to disable this feature. |
| `//scanner set filter [true|false]`  | Enable, disable, or toggle the filter feature. When enabled, the game's map will only show targets that match the current scan's search keys. Leave the arugment blank to toggle the value. |

## Examples
`//scanner autotrack blacktriple 0xD4 0xC0` -- Periodically widescan seeking out "Black Triple Stars" and its placeholders. Tracking will begin once a target is found.
`//scanner autoscan Ankabut 0x25` -- Periodically widescan seeking out "Ankabut" and its placeholder. No tracking will occur. A sound effect will be played if it is enabled. 
`//scanner set sound roar` -- Sets the sound effect upon finding a target to the "sounds/roar.wav" sound.
`//scanner set delay 45` -- Sets the auto-scan base delay to 45 seconds.
`//scanner set wiggle 15` -- Sets the auto-scan wiggle value to 15 seconds. A widescan will be preformed every 30-60 seconds (randomly).