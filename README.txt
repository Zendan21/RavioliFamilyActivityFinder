RAVIOLI FAMILY ACTIVITY FINDER 1.0.5

A community group finder for Project Ebonhold (WoW 3.3.5a). Players with the
addon can discover shared listings, request invitations, and manage applicants.

INSTALL
1. Remove the old EbonholdActivityFinder folder if it is installed.
2. Copy the RavioliFamilyActivityFinder folder into Interface\AddOns.
3. Restart WoW or type /reload.
4. Open it with /rav, /ravioli, or /ravfinder.

COMMANDS
/rav          Toggle the finder window
/rav reset    Reset the window position
/rav clear    Remove all local listings
/rav settings Open the settings window
/rav channel  Show channel and Ravioli diagnostics
/rav lock     Lock or unlock the floating launcher
/rav help     Show command help

FEATURES
- Shared activity listings between addon users through the RavioliFinder channel.
- Chat-safe hidden channel synchronization between addon users.
- Badge-safe sender cleanup and formatted RavioliFinder channel detection.
- Sender identity embedded in each packet to survive server-side chat-name rewriting.
- Unique per-login session identity for reliable self-versus-Ravioli detection.
- Immediate Ravioli registration at the transport layer before payload reassembly.
- Character-deduplicated Ravioli counts and compact session tokens for smaller packets.
- Paced channel send queue to prevent heartbeat and listing packets being flood-dropped.
- Compact single-packet listing advertisements with optional metadata sent separately.
- Dedicated direct listing and action protocols independent of the generic command/chunk decoder.
- Direct listing fields use the Ebonhold-tested chat-safe tilde separator.
- Direct listing advertisements are stored without using the generic payload decoder.
- Low-traffic 30-minute automatic synchronization.
- Manual Refresh with a 60-second lockout and staggered, coalesced responses.
- Open, Full, Closed, and Expired listing states with live group counts.
- Closed and Expired listings are owner-only and automatically removed after one hour.
- Request Invite, two-minute re-apply timing, organizer applicant list, Invite, Decline, and Whisper.
- Organizers cannot see or apply to mirrored copies of their own listings.
- Declined applicants cannot re-apply to the same organizer for two minutes.
- Declined applicants are removed immediately; invited applicants remain until they join the group.
- An active listing closes immediately if its owner joins another leader's group.
- Optional automatic invitations and automatic closing when full.
- Smart automatic error whispers distinguish HC mismatches, already-grouped applicants, full groups, and other failures.
- The custom automatic whisper message is used specifically for HC mode mismatches.
- Custom whispers support `{applicant_mode}`, `{group_mode}`, and `{error}` tokens.
- The concise default HC failure reply is: `Please go to {group_mode} to join.`
- `{group mode}` also works as an alternative spelling of `{group_mode}` in custom replies.
- Mandatory 5-30 minute listing expiry, start time, notes, and quest links.
- Authoritative Ebonhold hardmode-service detection for Normal and HC1-HC5, with chat badges as a fallback.
- Shift-click a quest while Create/Edit Listing is open to use its title.
- Category and search browsing.
- Movable group-themed launcher; right-click it to open settings.
- Optional full open/close synchronization between the Ravioli Finder and Quest Log.
- The main Finder stays visible with at most one secondary window.
- One active listing per organizer, enforced for Create and Reopen actions.

NOTES
- Every player who wants to browse or apply must install this addon.
- Version 1.0.0 was the first complete release.
- Shared discovery depends on the realm allowing a custom RavioliFinder chat channel.
- Protocol messages are filtered from normal chat by the addon.
