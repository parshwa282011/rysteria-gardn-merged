# Apple production: everything you need to send Rysteria to App Review

This is the "go live on the App Store" document. The setup before it (IDs, Sign in with Apple, the API key,
TestFlight) is [`APPLE.md`](APPLE.md); do that first. Everything below is filled in on
https://appstoreconnect.apple.com > **Apps > Rysteria**, except the build, which `scripts-phones/ios-deploy.sh
--production` uploads.

Apple's console changes its wording now and then. Where a name below is not on your screen, look for the
**bold** word. Anything that is a text for you to paste is in a quote block.

---

## 0. The order, in one screen

1. All of [`APPLE.md`](APPLE.md) done: App ID, Sign in with Apple (Services ID, key, email sources), app record, API key.
2. The **servers are up and stay up** (see 1). Apple opens the live site while it reviews.
3. A **demo account** exists on the website with its **email confirmed** (see 6).
4. `scripts-phones/ios-deploy.sh --testflight`, install it from TestFlight, go through the test list (see 2).
5. Fill the store page (3 to 7).
6. `scripts-phones/ios-deploy.sh --production` (raise `VERSION_CODE` first), pick the build on the version page, **Add for Review**.
7. Wait (8), answer anything in the Resolution Center, release (9).

---

## 1. Before anything: the servers

* **Apple reviewers play the real game on your servers, at any hour, for several days.** If `game.parshwa.blog` or
  `api-game.parshwa.blog` is down when they tap, the review fails with *2.1 App Completeness* (crash / unusable) and
  you start the queue again. Have the master, the game servers, gardn and the edge running on c1 with the Pi as the
  failover (the sync system), and look at `https://api-game.parshwa.blog/health` yourself every day until approval.
* `ios-deploy.sh --production` checks that `/`, `/privacy`, `/terms`, `/account` and `/login` answer 200 before it uploads.
* Email works (the demo login needs none, but a reviewer may try a sign up): SES **out of the sandbox** (KEYS.md).
* Keep `EMAIL_DAILY_LIMIT` at least at 50, a review can use a dozen codes.
* Apple sign in works on the website (a private window, "Sign in with Apple").

## 2. The test list on a real iPhone (TestFlight), before submitting

Install the build from TestFlight (internal testing) and tick every line. Fix anything that fails, upload a new build, repeat.

| Check | Expected |
|---|---|
| Launch | the game appears in landscape within a few seconds, no white screen |
| Not logged in | you land on `/login`; the Terms and Privacy links are there |
| Sign up with email | the code arrives; after it you are in the game |
| Log in again after closing the app | still logged in |
| Sign in with Apple | the Apple sheet opens (Safari-style sheet), returns to the game, a new user is asked for a username and a password |
| Sign in with Apple, **Hide My Email** | works; a password reset for it mails the code |
| Sign in with Google and Discord | the same: sheet, back to the game |
| Play 5 minutes | no crash, chat works (level 3 or more), leaderboard opens at `/leaderboard` |
| A link to another site | opens in Safari, not inside the game |
| Airplane mode, then reopen | no crash (a blank game page is allowed) |
| **Account > Manage account** | `/account` opens: username, email, linked sign-ins |
| **Delete account** (with a spare account!) | password, code, username typed: the account is gone, you land logged out |
| Rotate / background / reopen | the game keeps running or reconnects |

## 3. App Information (left menu)

| Field | Put |
|---|---|
| Name | `Rysteria` (max 30 characters; if taken: `Rysteria: Flower Arena`) |
| Subtitle | `Online petal battles` (max 30) |
| Category | Primary **Games** > subcategory **Action**; secondary **Games > Adventure** |
| Content Rights | "Does your app contain, show, or access third-party content?" **No** |
| Privacy Policy URL | `https://game.parshwa.blog/privacy` |
| Age Rating | see 4 |

## 4. Age rating (App Information > Age Rating > Edit)

Apple's questionnaire gets rewritten every year or two; answer **honestly** whatever the exact wording is. For Rysteria:

| Topic | Answer |
|---|---|
| Violence, cartoon or fantasy | **Infrequent or mild** (flowers and bugs fight; no blood) |
| Violence, realistic / graphic / sexual content / nudity / profanity / horror / drugs / alcohol / tobacco / gambling / contests | **None** |
| Unrestricted web access | **No** (the app opens one game; other links go to Safari) |
| Messaging and chat / user-generated content | **Yes** (players chat; it is filtered) |
| Advertising | **No** |
| Loot boxes or purchases | **No** (nothing is sold) |
| Medical / health | No |

Expect a rating of about **9+ to 13+** (the chat usually decides it). If Apple asks for a "made for kids" category: no.

## 5. Pricing, availability, and the app's version page

**Pricing and Availability:** price **Free** (tier 0), all countries and regions you want (to skip the EU's extra rules, untick EU countries).

**Prepare for Submission** (the version page, "1.0"):

| Field | Put |
|---|---|
| Promotional Text (170) | `Fight bugs, collect petals and climb the leaderboards with players from all over the world.` |
| Description (4000) | below |
| Keywords (100, commas, no spaces) | `petals,flower,io,multiplayer,survival,arena,online,battle,craft,minigames` |
| Support URL | `https://game.parshwa.blog/privacy` (it shows how to reach you) |
| Marketing URL | `https://game.parshwa.blog/` |
| Version | `1.0` |
| Copyright | `2026 Tejashkumar Shah` |
| What's New | not asked for a first version (for 1.1: `Bug fixes and improvements.`) |

> **Description to paste**
>
> Rysteria is a free online game where you play as a flower in a world full of bugs, other players and mysteries.
>
> • Fight mobs with your petals and level up to unlock more petal slots
> • Collect and craft stronger petals, from common to ancient
> • Take on other players in the PvP zone, or team up in squads
> • Try the minigames: capture the flag, team deathmatch and hide and seek
> • Climb the public leaderboards and share your stats page
> • Sign in with Apple, Google, Discord or email; your progress follows your account everywhere
>
> Rysteria is free to play, with no purchases and no ads. You can delete your account and all its data yourself from the
> account page, at any time.

## 6. Screenshots

The app is iPhone only, landscape. App Store Connect needs **iPhone 6.9"** (the other sizes are scaled from it):
**2868 × 1320**, **2796 × 1290** or **2736 × 1260** pixels (landscape). 3 to 10 screenshots, PNG or JPEG, no alpha, no
device frame needed.

Take them in the Simulator: `scripts-phones/ios-run.sh --sim "iPhone 17 Pro Max"` (any 6.9" iPhone), log in, put the game
in a nice moment, **Cmd+S** (saved to the Desktop). Suggested set: 1) the world with a crowd of mobs, 2) the petal crafting
screen, 3) the leaderboard (`/leaderboard`), 4) a minigame, 5) the title screen with the squad menu. Show the real game,
no text added that is not in the game, no other platform's names (no "Android", no "Google Play" badges).

## 7. App Privacy ("nutrition label") and the other declarations

**App Privacy > Get Started.** "Do you or your third-party partners collect data from this app?" **Yes**, then for each:

| Data type | Linked to the user | Used to track | Purpose |
|---|---|---|---|
| Contact Info: Email Address | Yes | No | App Functionality |
| Contact Info: Name (the display name Apple/Google/Discord gave) | Yes | No | App Functionality |
| User Content: Other User Content (chat messages) | Yes | No | App Functionality |
| Identifiers: User ID | Yes | No | App Functionality |
| Usage Data: Product Interaction (gameplay progress and scores) | Yes | No | App Functionality |

No analytics, no ads, no data broker, **no tracking** (so no App Tracking Transparency prompt). Publish the answers.

**Export compliance** (when you select a build, or the first time): the app uses only standard HTTPS. The project already
declares `ITSAppUsesNonExemptEncryption = NO`, so Apple does not ask. If it does: *Yes it uses encryption, but it is exempt
(only HTTPS)*.

**Advertising Identifier (IDFA):** No. **Content rights:** No third-party content. **Sign-in with Apple:** offered (guideline 4.8).

## 8. App Review Information (the part that decides it)

| Field | Put |
|---|---|
| First / last name, phone, email | yours (Apple calls this number only if something is wrong) |
| **Sign-in required** | **tick**, then Username and Password of the **demo account** below |
| Notes | the text below |

**The demo account:** on the website make an account `applereview` (any name), with a real email you can read; sign up,
**type the code from the email so the address is confirmed** (an unconfirmed account stops at the confirmation screen and
the reviewer is stuck: that is the most common reason for a rejection here), log in once and play a minute so it has
some progress. Write its username and password in the fields. Keep that account until the app is approved.

> **Notes to paste (App Review Information > Notes)**
>
> Rysteria is a free multiplayer game. The game itself runs on our servers (game.parshwa.blog); this app is its iOS
> front end, so the servers must be reachable (they are online 24/7).
>
> HOW TO TEST: open the app and log in with the demo account above (or tap Sign up: a confirmation code is emailed).
> Sign in with Apple, Google and Discord are on the same login page. Tap Play to enter the world; move with the touch
> controls / mouse and use the petals around your flower.
>
> ACCOUNT DELETION (5.1.1(v)): in the game open the account screen (top of the menu), tap "Manage account", then
> "Delete my account" at the bottom. It asks for the password, a 6 digit code sent to the account's email (or Discord)
> and the username typed back, then permanently deletes the account and its data and revokes the Sign in with Apple
> token. Please use a different account for this test, or tell us and we will make another demo account.
>
> USER-GENERATED CONTENT (1.2): in-game chat needs level 3, is filtered for objectionable words, and abusive players
> are removed; players report abuse to the address in our Privacy Policy (https://game.parshwa.blog/privacy), which we
> answer and act on within 24 hours.
>
> The app uses the system browser sheet (ASWebAuthenticationSession) for Google, Discord and Apple sign-in and opens
> every other link in Safari. It does not collect data beyond what the Privacy Policy states, uses no ads or tracking,
> and sells nothing.

## 9. The build, then submit

1. Raise `VERSION_CODE` in `scripts-phones/phones.env` (a number Apple has not seen), keep `VERSION_NAME=1.0`.
2. `scripts-phones/ios-deploy.sh --production`. It checks the live site, asks you to type `production`, archives, signs
   (automatic signing with your team), uploads, and remembers the build number. Apple emails when processing is done
   (5 to 60 minutes). Fix the **Missing Compliance / Missing icon / invalid** emails if one arrives (the icon: README).
3. App Store Connect > Rysteria > the version page > **Build** > **+** > pick it.
4. Check every field of 3 to 8 is filled; **Version Release**: choose **Manually release this version** (you press the
   button when it is approved) or *Automatically*.
5. **Add for Review**, then **Submit to App Review**.

## 10. While you wait

| Status | Meaning |
|---|---|
| Waiting for Review | in the queue (usually under a day, sometimes three) |
| In Review | a person is playing it (a few hours) |
| Pending Developer Release | approved, you press **Release this Version** |
| Ready for Sale | live |
| Rejected | Apple wrote why: open **Resolution Center** (the message under the app's name) |
| Metadata Rejected | only the page text/screenshots: fix them and **resubmit without a new build** |

If an email arrives asking for information: answer in the Resolution Center within a couple of days. If it is a
mistake, you may **reply and argue politely** or use *Appeal* (App Review Board). An urgent bug fix can ask for an
**Expedited Review**.

## 11. Replies to the usual rejections

| Message | What to do |
|---|---|
| **2.1** "app crashed / server did not respond" | the servers were down: say they are 24/7, check `/health`, ask them to retry; fix the cause |
| **2.1** "needs a demo account" / "could not sign in" | your demo account's email was unconfirmed or the password was wrong: fix and reply with the working login |
| **4.2** "minimum functionality, a repackaged website" | reply: *"Rysteria is a real-time multiplayer game with its own accounts, progress, leaderboards and live servers. The app is an iOS front end of that game (like other online games that load from servers), adds system sign-in (Sign in with Apple, Google, Discord) and account management, and can not work offline because the game world is online."* If they insist, add something native (a no-connection screen, haptics) and resubmit |
| **1.2** "no way to report / block users" | add a **Report** button in the game (ask me to build it) and say chat is filtered; or explain the report address in the notes |
| **5.1.1(v)** "account deletion" | point to Account > Manage account > Delete my account (steps are in the notes) |
| **4.8** "login services" | Sign in with Apple is offered on the login page; check it shows (Apple keys set on the master) |
| **5.1.1** "privacy policy" | the URL is `https://game.parshwa.blog/privacy`; check it opens, and the label answers (7) match it |
| **Guideline 5.2/2.3** "metadata" | screenshots must show the real game; remove any text overlay and other brands |

## 12. After approval

* Press **Release this Version** (if manual). It is in the store within a couple of hours.
* Watch crashes and feedback: Xcode > Window > Organizer > Crashes, and TestFlight feedback.
* **Updates**: only when `phones/ios` changes. Raise `VERSION_NAME` (`1.0.1`) and `VERSION_CODE`, `ios-deploy.sh --production`, make a new
  version page (+ in the sidebar), pick the build, write *What's New*, submit. Game updates never need this: the app
  loads the website.
* Keep the demo account and the Apple keys: the `.p8` (Sign in with Apple), the API key, and `APPLE_*` in `master.env`.
* Apple's account-change notices arrive at `ADMIN_EMAIL`.
