from pathlib import Path
import json, html, shutil
ROOT=Path('/Users/roeylibfeld/Documents/KARI Creatives/DaBin/marketing/launch-kit-2026-10-04')
P=ROOT/'01_Launch_Playbook'; C=ROOT/'02_Copy'
P.mkdir(parents=True,exist_ok=True); C.mkdir(parents=True,exist_ok=True)
files={}
files[P/'DaBin_Launch_Strategy.txt']='''DABIN / LAUNCH STRATEGY
Prepared 4 October 2026. Use after verified App Store publication.

POSITIONING
A little desktop robot for the useful bits of your day.
Lead with: Save now. Find it later. Keep it on your Mac.
Supporting message: DaBin keeps notes, links, images, files and tasks together on your Mac. Drop something onto the robot, keep it with a project, and find it again.

The robot earns attention. A clear save-and-find demonstration earns the download. Local storage and no account reduce setup friction. Show one useful outcome in every post.

PRIMARY AUDIENCE: DESIGNERS AND CREATIVE FREELANCERS
Problem: project references live in scattered screenshots, tabs, files and notes.
Example: a fictional 'Studio Refresh' branding project containing an image, a saved design link, a note and a task.
First useful action: save three fictional references and find one again by searching a word inside a saved screenshot.
Creative angle: 'Catch the useful bits between ideas.'
Avoid presenting DaBin as a shared mood-board service or full design tool. It has no cloud sync or team workspace.

SECONDARY AUDIENCES: TEST AFTER THE FIRST WEEK
Students: collect lecture screenshots, reading files and notes into a project, then search saved supported content. Use a fictional class; do not claim citation management or study outcomes.
Developers: collect a documentation link, screenshot, named snippet and task into a project. Do not claim code execution, AI answers or integrations that are not shipped.
Independent professionals: save a useful link or meeting note and keep the next task beside it. Do not imply automatic meeting capture.

THE THREE DEMOS
1. Feed DaBin (22 seconds). A playful robot sequence opens the clip; then show a real app view saving and finding fictional content. Animated sequences are brand animation, not a recording of actual app behavior. Use 04_Video/DABIN__FEED_DABIN__LANDSCAPE.mp4 for website/press and the portrait version for short-form social. End with a visible download action after the App Store URL is live.
2. Where did that screenshot go? Show a saved fictional screenshot with the word 'terracotta', a neutral filename, and a search for that word returning it. Claim: find words in saved supported screenshots. Search is local, not a search of every file on the Mac or semantic AI search.
3. One project, useful bits together. Put a link, image, note and task into the fictional Studio Refresh project; show the project's resources. Organization is optional.

CHANNEL PRIORITY
1. App Store product page + landing page. A download should lead to a truthful, readable product page with a functioning support/contact route.
2. One Mac community launch. Start with r/macapps only if its current rules and account eligibility are met. Disclose the developer relationship and AI involvement accurately. Do not repeat an app promotion inside the cooldown window.
3. Targeted creator/publication outreach. Start with 3-5 highly relevant routes from Creator_and_Publication_Targets.html, then another small batch in week two. Read recent coverage yourself and add one specific, truthful reason for the fit. All supplied messages are unsent drafts.
4. Short-form demos on your existing social accounts. Publish 2-3 useful clips a week, with a different problem or audience each time. Replies matter more than repeating the announcement.
5. Product Hunt. Choose a day when the app, support and maker are ready. Use the feed demo, truthful listing and maker comment. Ask for questions and feedback, never upvotes.
6. Apple featuring nomination. If publication is at least three weeks away, submit the launch plan early. If already published, use a future meaningful update with an actual date and change; do not invent one to fit the form.

LANDING PAGE
One headline, one 22-second demonstration, three outcomes, compatibility, concise privacy explanation and an App Store button. Keep the phrase 'DaBin for Mac' in page title and description. Use the local page supplied in 05_Landing_Page as a reviewable draft. Replace placeholders before deployment. Do not invent a founder story, testimonials, download counts or Apple endorsement.

APP STORE ASSETS
The source submission pack has three real 1440 x 900 native screenshots: Inbox, Projects and Focus. Lead with an outcome and readable UI. A search/OCR screenshot is an additional proposed capture, not a claim that an existing image proves search. Compare all screenshots with the published build. The Blender robot video is a social/website brand film; Apple previews require device-captured app footage and separate specification review.

FIRST MONTH
Week 1: announce, answer questions, establish a baseline, contact first 3-5 targets.
Week 2: show saved-screenshot text search, contact the next 3-5 targets, follow up once where welcome.
Week 3: test a student or developer use case, answer the most common question in a clip.
Week 4: review the month, retain the strongest message, share only actual fixes or observations, and prepare the next useful demonstration.
The exact day-by-day plan is in 30_Day_Calendar.html and 30_Day_Calendar.json. Day 1 is verified public availability, not this package's creation date.

MEASUREMENT
Use Apple campaign links when available, native platform metrics and voluntary feedback. Keep per-channel results distinct and record attribution limits. There is no in-app analytics: do not report inferred product activation or retention as measured facts. Use the supplied empty tracker, not invented goals. A reasonable operational target is 10 carefully selected pitches across the month, with up to 10 more only if fit and response justify it. This is an activity target, not a forecast of downloads.

WORKLOAD AND SPEND
Plan for 30-45 minutes on publishing days, a short daily reply check in launch week, and one 45-minute weekly review. Start with existing accounts and organic distribution. Paid creator partnerships are optional later and require an explicit budget decision; this kit makes no commitments.

USE THE KIT
Fill [[APP_STORE_URL]], [[WEBSITE_URL]], [[CONTACT_EMAIL]] and other clearly marked owner fields. Confirm the live build matches the claims. Choose one primary audience and one main clip. Publish only after the release is visible and downloadable in the intended territories. No outreach, post, nomination or website has been submitted by this package.
'''
files[P/'Launch_Checklist.txt']='''DABIN / LAUNCH CHECKLIST
Prepared locally. Nothing has been posted, sent, submitted or deployed.

BEFORE PUBLICATION
[ ] Final distributed app/build is verified; Apple approval and the planned release method are complete.
[ ] Price is Free in intended territories. Avoid 'free forever' unless there is an explicit permanent commitment.
[ ] App Store URL, supported territories and publication date are confirmed.
[ ] Website URL, public support route and contact email are working.
[ ] Replace [[APP_STORE_URL]], [[WEBSITE_URL]], [[CONTACT_EMAIL]], [[DEVELOPER_NAME]], [[LAUNCH_DATE]], [[RELEASE_NOTES_URL]] and all channel-specific fields.
[ ] Final screenshots and demonstrations match the shipping app. Fictional examples only; no private capture archive or KARI material.
[ ] Any stylized robot animation is described as brand animation rather than a literal app recording.
[ ] Show Apple Silicon + macOS 14 or later where compatibility affects the download choice.
[ ] Review privacy wording: no account, advertising, analytics or cloud sync; local recognition of saved supported content; optional manual-link previews can contact websites.
[ ] Verify any fonts, artwork, music and voice licensing; keep their provenance with the source files.
[ ] Read r/macapps rules again; check promotion timing/account eligibility and choose the truthful AI disclosure.
[ ] Read Product Hunt launch guidance again and use a personal maker account.
[ ] Watch all video exports with sound and muted; check subtitles, legibility, CTA and crop on a phone.
[ ] Check social copy with the actual URL; shorten if a platform's current limit requires it.
[ ] If seeking launch featuring, nominate at least three weeks ahead where practical; otherwise prepare an actual future update nomination.

DAY 1: AFTER THE RELEASE IS VERIFIED PUBLIC
[ ] Open the App Store listing from an ordinary browser/device and confirm the download is available.
[ ] Replace 'coming soon' or draft labels on the public landing page and set its primary download link.
[ ] Publish the main feed clip on one primary social channel, with the approved post copy.
[ ] Publish one rule-compliant community announcement; be present for questions.
[ ] Share the factsheet and app link with the first small set of targets using tailored messages.
[ ] Record campaign/channel, exact asset, timestamp, destination URL and minutes spent.
[ ] Answer compatibility and privacy questions using Support_and_Reply_Copy.txt.

FIRST 7 DAYS
[ ] Check whether App Store Connect campaign links are available after the app has live download data; do not fabricate provider tokens.
[ ] Give each major channel an Apple-generated campaign link as soon as available.
[ ] Log the earliest posts as untagged if campaign links were not yet available.
[ ] Make the saved-screenshot text-search clip from the real shipping app.
[ ] Collect voluntary feedback; ask what users saved and whether they could find it again without asking for private content.
[ ] Reply once to each meaningful question; do not pressure users for ratings or upvotes.
[ ] Reconcile support FAQ with actual questions.

WEEKLY
[ ] Compare like date ranges; preserve unavailable/withheld metrics as such.
[ ] Record impressions/views and product-page/download metrics separately.
[ ] Review time spent per useful reply, campaign download and qualified outreach response.
[ ] Follow up once after about a week only where appropriate; stop when declined or unanswered after that.
[ ] Publish a useful answer or workflow, not another identical launch message.
[ ] Pause promotion of a broken feature and fix the claim or app before reusing the clip.

END OF MONTH
[ ] Review observed results without inventing attribution, retention or a success story.
[ ] Keep the best-supported audience/message for month two.
[ ] Decide whether any paid experiment deserves a capped budget.
[ ] Refresh claims and screenshots against the currently public build.
[ ] Archive the final copy, assets, source URLs and real campaign results.
'''
files[P/'Claim_Guardrails.txt']='''DABIN / MESSAGING CLAIM GUARDRAILS
Basis: user intends a free release; local source submission pack 0.4.31 (86), prepared 4 October 2026. Source metadata is DRAFT_NOT_FOR_UPLOAD and does not establish approval or public availability.

SAFE CLAIM -> REQUIRED LIMIT
'Free Mac app' -> Confirm actual Free pricing in the intended launch territories. Do not promise free forever or invent a monetization plan.
'No account, advertising, analytics or cloud sync' -> Describes the reviewed app source. Apple/platform campaign reports are separate from analytics inside DaBin. Recheck the shipping build.
'Saved content stays on your Mac' -> DaBin stores captures locally. User-chosen exports/backups may be saved to a folder synced by another service. Avoid 'nothing ever leaves your Mac'.
'Local text recognition' -> Recognizes text in supported content saved into DaBin using local Apple frameworks. It does not scan every file, record the live screen, answer with AI or provide semantic search. Recognition can be imperfect; very large documents can be partially indexed.
'Find words inside saved screenshots' -> Save the screenshot first; demonstrate an actual matching word in a supported image with a neutral filename. Do not imply search of all past screenshots.
'Optional Auto Capture' -> Off by default with independent clipboard and selected screenshot-folder channels. Only later clipboard changes/new images after activation are eligible. Do not say 'captures everything'.
'Privacy by design' -> Be specific. App Sandbox is present; DaBin does not separately encrypt the archive and does not promise forensic secure erasure. Do not claim end-to-end encryption or immunity from sensitive captures.
'Website previews are optional' -> Off by default; enabled previews may contact manually saved sites and their resources. Automatically captured links do not fetch previews. Opening a saved URL uses a browser and its normal network behavior.
'Made for Mac' -> Apple Silicon Macs, macOS 14 or later. Do not imply Intel, Windows, iPhone or cross-device sync support.
'Focus timer' -> A running timer shows a robot alarm; clicking dismisses it and does not complete the task. Do not promise to prevent distractions or improve output by a numerical amount.
'Accessible' -> State only features demonstrated on the exact shipping build. Do not declare full VoiceOver support or Apple Accessibility Nutrition Labels without the required evaluation.
'On the Mac App Store' -> Use after verified publication. No 'Apple featured', award badges or Apple endorsement without documented selection.
'Feed DaBin' film -> Blender scenes are playful brand animation. Real app views must remain visibly recognizable as actual screenshots/recordings. Never label the entire brand film a native App Store preview.

TONE
Friendly, direct and useful. The robot is a companion, not an AI agent. Prefer 'Save a screenshot; find a word inside it later' to inflated claims about an intelligent second brain. Always spell the product DaBin. Do not invent testimonials, user numbers, founder motivation, speed claims, subscription comparisons or future features.

PUBLICATION FIELDS
Mandatory placeholders: [[APP_STORE_URL]], [[WEBSITE_URL]], [[CONTACT_EMAIL]]. Other owner fields remain explicit in copy. A placeholder is a work item, never a public link. Do not publish unreplaced placeholders.

PRIVACY IN DEMOS
Use the fictional Studio Refresh project, example.com links and fabricated design notes. Do not use real clipboard content, client names, desktop filenames, personal bookmarks, email addresses, notifications or the KARI screenplay/reference library.

STATUS
This marketing package is prepared and local. All outreach is unsent. No external posting, website deployment, nomination or Apple metadata upload is included in its creation.
'''
files[P/'Campaign_Measurement.txt']='''DABIN / CAMPAIGN MEASUREMENT
Use only observed values. campaign-tracker.json is empty by design.

AIM
Find which demonstration and audience bring relevant downloads and useful feedback. DaBin has no in-app analytics, so saving/searching a first item or continued use is not measured inside the app.

SOURCES
App Store Connect: first-time downloads, product page views and campaign data when available. Apple's campaign feature may appear only after live analytics/download data; Apple advises checking after at least 24 hours. Individual metrics have minimum thresholds; unavailable or withheld values are not zero.
Native social platforms: views/impressions and engagement using their own definitions. A video view is not a website visit or download.
Outreach: number of tailored pitches, replies, evaluations and actual coverage. A recipient's acceptance of a pitch is not a download.
Voluntary feedback: ask one optional question in a reply or email - 'What did you save first, and could you find it again?' Store only what people knowingly share; do not request their actual files or private screenshots.

CAMPAIGN NAMING
Use simple short tokens generated in App Store Connect, for example:
feed_social_launch
screenshot_search_social
reddit_macapps_launch
producthunt_launch
creator_[shortname]
website_main
These are proposed campaign names, not working links. Obtain real links/provider token from App Store Connect. Use the Apple-generated link exactly. Do not fabricate IDs, provider tokens or a functioning attribution URL.

DAY 1 BEFORE LINKS APPEAR
Use the real untagged App Store URL. Log publication time and destination. Mark measurement 'untagged launch / source attribution unavailable'. A download spike on the same day is association, not proven channel attribution.

WEEKLY ROUTINE (45 MINUTES)
1. Fix one reporting window, e.g. Day 1-7; use the same date range for comparable campaigns.
2. Record each channel/asset, minutes spent, live link, views, App Store page views/downloads if available, replies and issues.
3. For a channel with both available page views and first-time downloads, calculate downloads / product page views. Keep the numerator/denominator scope identical. Do not call it a causal conversion rate if scopes differ.
4. For limited organic time, compare downloads / hours spent where both are known. This is an operational efficiency estimate, not customer acquisition cost or a forecast.
5. Read qualitative replies. Pick one audience/problem to repeat and one unclear claim to improve.
6. Leave null values as null; note 'not available', 'below threshold', 'untagged' or 'not collected'.

ATTRIBUTION LIMITS
Apple's guide counts first-time downloads within 24 hours of campaign-link use and describes last-link credit when several campaign links were clicked. Read current definitions before reporting. Different platforms use different view/click definitions, and campaign results do not include every indirect discovery path. No telemetry SDK is required by this plan.

MONTH-END DECISIONS
Strong reach / few App Store page views: make the benefit and CTA clearer.
Page views / few observed downloads: verify compatibility, Free price, product screenshots and support trust.
Downloads / confused feedback: prioritize onboarding explanation and fix the repeated problem.
Too little available data: keep the experiment small and collect more voluntary feedback; do not claim failure or success from missing values.

DO NOT REPORT
Invented download forecasts; activation/retention without a real data source; average time saved; worldwide support from a few replies; guaranteed creator coverage; or 'zero downloads' when Apple withholds the metric.

SOURCE
Apple campaign links: https://developer.apple.com/help/app-store-connect-analytics/acquisition/campaign-links
Checked 4 October 2026. Reporting rules can change; recheck during launch.
'''
files[C/'Messaging_and_Brand_Voice.txt']='''DABIN / MESSAGING & BRAND VOICE
Ready for owner review. Replace live-link fields before use.

PRIMARY LINE
Save now. Find it later. Keep it on your Mac.

BRAND LINE
A little robot for the useful bits of your day.

ONE SENTENCE
DaBin is a free Mac app that keeps your notes, links, images, files and tasks together locally, with a little robot you can drop things onto.

SHORT DESCRIPTION (43 WORDS)
Meet DaBin, a little robot for the useful bits of your day. Save notes, links, images, files and tasks on your Mac, keep related items with a project, and find them again with local search. Free. No account required. Apple Silicon, macOS 14+.

MEDIUM DESCRIPTION
Useful things turn up while you're doing something else: a design reference, a link, a screenshot, an idea. DaBin gives them a place on your Mac. Drop content onto the desktop robot, paste into the board, or create a note or task. Keep related captures with a project and search saved supported images and documents for their text. DaBin is free, with no account, ads, analytics or cloud sync. Optional website previews are off by default and can contact manually saved sites when enabled. Requires an Apple Silicon Mac with macOS 14 or later.

AUDIENCE OPENERS
Designers: Keep a project's useful references close.
Students: Keep reading notes and saved screenshots together.
Developers: Save the link, snippet and next step with the project.
General: Where did that useful screenshot go?

OUTCOME HEADLINES
Catch the useful bits.
Find words inside saved screenshots.
Keep a project together.
Give one task your attention.
Your little desktop companion.

CTA OPTIONS
Get DaBin for Mac.
Download free on the Mac App Store.
Try saving three useful things.
Save it. Search it. Get back to work.

VOICE
Say 'save', 'drop', 'find' and 'keep'. Use concrete examples. A little warmth is welcome; never make the robot sound like it can think, answer questions or search the whole computer. One benefit per post. Describe the local model plainly; no exaggerated security or productivity promises.

PRIVACY LINE
No account, ads, analytics or cloud sync. Saved captures and recognized text stay on this Mac. Optional manual-link previews can contact websites.

LINKS
App Store: [[APP_STORE_URL]]
Website: [[WEBSITE_URL]]
Contact: [[CONTACT_EMAIL]]
'''
files[C/'Reddit_MacApps_Post.txt']='''DABIN / R-MACAPPS LAUNCH POST
UNSENT DRAFT. Use only after verified publication. Read current subreddit rules and account eligibility first. The checked developer format requires problem, named comparison, price/link, changelog or roadmap, and accurate AI disclosure. Respect the promotion cooldown. The body below is deliberately concise; fill its fields before posting.

TITLE
I made DaBin: a free local Mac app for saving useful bits, with a desktop robot

BODY
Developer here - I'm [[DEVELOPER_NAME]], the maker of DaBin.

Problem: Useful screenshots, links and notes are easy to save and hard to find again when they're scattered.

Compare: Apple Notes and Finder already cover notes and files. DaBin's approach puts saved screenshots, links, files, project resources and tasks in one local capture board, with a robot drop target and text search across saved supported content. It's an alternative workflow, not a claim that those tools lack text search.

Price + link: Free for Apple Silicon Macs running macOS 14 or later. [[APP_STORE_URL]]

Changelog: [[RELEASE_NOTES_URL]]
AI disclosure: [[SELECT_TRUTHFUL_CURRENT_RULE_CATEGORY]]

The 22-second demo shows a fictional project: drop in a reference, keep it with a project, then find it again. Text recognition runs on your Mac. Search covers things saved into DaBin. Auto Capture and website previews start off; enabled manual-link previews can contact sites. No account, ads, analytics or cloud sync.

I'd value feedback on saving and finding project references. What felt clear, and what was confusing?

ATTACH
04_Video/DABIN__FEED_DABIN__LANDSCAPE.mp4, or one clear real screenshot if video posts are unavailable.
Do not ask for upvotes. If the current rules require a different format, adapt before posting.

AI DISCLOSURE FIELD
Do not infer the category from marketing assets or select 'None' by default. The source rule uses Vibe Coded, Human Validated, Code Completion and None. The developer must pick a truthful category under the current definitions.

SOURCE
https://www.reddit.com/r/macapps/comments/1r6d06r/new_post_requirements_to_combat_low_quality/
Checked 4 October 2026; the notice describes an experiment, so reread current rules on posting day.
'''
files[C/'Product_Hunt_Copy.txt']='''DABIN / PRODUCT HUNT COPY
UNSENT DRAFT. Publish after the product is downloadable and links are complete.

NAME
DaBin

TAGLINE
A little Mac robot for saving and finding useful bits

DESCRIPTION
Save notes, links, images, files and tasks on your Mac. Drop things onto DaBin's desktop robot, keep them with a project, and search words in saved supported screenshots and documents locally. Free. No account, ads or cloud sync. Apple Silicon, macOS 14+.

WEBSITE / DOWNLOAD
[[WEBSITE_URL]]
[[APP_STORE_URL]]

FIRST MAKER COMMENT
Hi Product Hunt - I'm [[DEVELOPER_NAME]], the maker of DaBin.

DaBin gives the useful bits of your day a place on your Mac: a screenshot, a reference link, a note or the next task. The desktop robot is a drop target; the board keeps saved content and project resources together.

The demo uses a fictional design project. Save a few references, then search a word inside a saved screenshot. Recognition happens locally and search covers supported content saved into DaBin.

It's free, requires no account and has no ads, analytics or cloud sync. Auto Capture is optional and off by default. Optional previews for manually saved links can contact the linked sites when enabled.

It runs on Apple Silicon Macs with macOS 14 or later. I'd like to hear whether the save-and-find workflow feels useful, especially for design references. Ask anything about capture, projects or local search; I'll be here to reply.

[[APP_STORE_URL]]

GALLERY ORDER
1. Outcome-led capture/Inbox image.
2. Feed DaBin brand film; label it as an animated introduction where context is needed.
3. Real Projects view with fictional references.
4. Real saved-screenshot search recording/screenshot once captured from the public build.
5. Real Focus view only if room; one clear benefit beats a feature collage.

LAUNCH NOTE FOR YOUR OWN CHANNELS
DaBin is on Product Hunt today. It's a free Mac app for saving and finding useful bits, with a little desktop robot. Take a look and tell me what you think: [[PRODUCT_HUNT_URL]]

REPLIES
Compatibility: Apple Silicon Macs with macOS 14 or later.
Data: Saved captures and recognized text are local. No account, ads, analytics or cloud sync. Optional manual-link previews can contact websites.
Search: It searches supported content saved into DaBin; it doesn't search the entire Mac or answer with AI.

Do not ask for upvotes. Use your own maker account, verify the current field limits in the submission form, and choose a day when you can answer questions. No ranking or featuring outcome is promised.
SOURCE: https://www.producthunt.com/launch (checked 4 October 2026).
'''
files[C/'Social_Posts.txt']='''DABIN / SOCIAL POSTS
UNSENT. Use after public availability. Fill live URLs and check platform limits with the real link. Every post has one job. Use 03_Graphics and 04_Video assets; do not expose personal saved content.

01 / LAUNCH / SHORT (X, BLUESKY, MASTODON)
Meet DaBin: a little robot for the useful bits of your day.
Save notes, links, images, files and tasks on your Mac - then find them again.
Free. No account. Apple Silicon, macOS 14+.
[[APP_STORE_URL]]
Attach: feed film, landscape or portrait as supported.

02 / SCREENSHOT SEARCH / SHORT
Where did that screenshot go?
Save it into DaBin, then find a word inside it with local text search.
Free for Apple Silicon Macs, macOS 14+.
[[APP_STORE_URL]]
Attach: real saved-screenshot search demo; neutral filename, visible matching word.

03 / DESIGNER / SHORT
A reference image. A useful link. A note for later.
Keep a project's useful bits together in DaBin, a free local Mac app with a little desktop robot.
Apple Silicon, macOS 14+.
[[APP_STORE_URL]]
Attach: real fictional Studio Refresh Projects view.

04 / LOCAL / SHORT
No account, ads, analytics or cloud sync.
DaBin keeps your saved captures and recognized text on your Mac. Optional manual-link previews can contact websites.
Free. Apple Silicon, macOS 14+.
[[APP_STORE_URL]]
Attach: local-storage card.

05 / FOCUS / SHORT
Keep the next task beside the reference that inspired it.
DaBin brings saved content, projects and a focus timer together on your Mac.
Free. Apple Silicon, macOS 14+.
[[APP_STORE_URL]]
Attach: real Focus view.

06 / STUDENT TEST / SHORT
Reading notes, a saved lecture screenshot, and the next task - one local project.
Try DaBin with fictional sample content first. Search finds words in supported content you've saved.
Free for Apple Silicon Macs, macOS 14+.
[[APP_STORE_URL]]

07 / DEVELOPER TEST / SHORT
Save the documentation link, the useful snippet and the next step with a project.
DaBin is a free local Mac app for those useful bits between tasks.
Apple Silicon, macOS 14+.
[[APP_STORE_URL]]

08 / LINKEDIN LAUNCH
Useful references often arrive while you're busy doing something else.

DaBin gives them a place on your Mac. Drop an image, paste a link or write a note. Keep related captures and tasks with a project, then find them again with local search - including words in saved supported screenshots and documents.

The little desktop robot makes saving approachable; the app keeps the content local. No account, ads, analytics or cloud sync. Optional manual-link previews are off by default and can contact websites when enabled.

DaBin is free on the Mac App Store for Apple Silicon Macs with macOS 14 or later.
[[APP_STORE_URL]]

If you collect design references, I'd value your feedback: was it easy to save three useful things and find one again?
Attach: feed film + actual Projects screenshot.

09 / INSTAGRAM OR REELS CAPTION
Feed DaBin the useful bits.
A screenshot. A link. A note. Keep them with a project and find them again on your Mac.

Free Mac app. No account required.
Apple Silicon + macOS 14 or later.
Download: [[APP_STORE_URL]] (place the working link in your profile if the platform doesn't make captions clickable).

#DaBin #MacApps #DesignWorkflow #Productivity
Attach: DABIN__FEED_DABIN__PORTRAIT.mp4. On-screen text must explain the benefit with sound off.

10 / YOUTUBE SHORTS
Title: Feed DaBin: save it now, find it later on your Mac
Description: Meet DaBin, a free Mac app that keeps notes, links, images, files and tasks together locally. Search words in supported content saved into DaBin. No account, ads, analytics or cloud sync. Optional manual-link previews can contact websites. Requires Apple Silicon + macOS 14 or later. Download: [[APP_STORE_URL]]
Attach: portrait feed film. Do not title it an App Store preview.

11 / CREATOR COVERAGE FOLLOW-UP
[[CREATOR_NAME]] tried DaBin and showed [[ACTUAL_WORKFLOW_SHOWN]]. Here's their independent take: [[COVERAGE_URL]]
Only use after actual coverage; quote briefly and accurately, with permission where required. Never prefill endorsements or imply they were paid unless that is true and disclosed.

12 / MONTH-END UPDATE
One question that came up after DaBin's launch was [[ACTUAL_QUESTION]]. This short demo shows [[VERIFIED_ANSWER_OR_FIX]].
DaBin is free for Apple Silicon Macs with macOS 14 or later: [[APP_STORE_URL]]
Do not invent a popular question, download count or update. If no such evidence exists, publish the simple saved-screenshot demo instead.

ALT TEXT EXAMPLES
Feed film poster: DaBin's metallic desktop robot beside three fictional saved items: a reference image, a link and a note. Caption: Save now. Find it later. Keep it on your Mac.
Project screenshot: DaBin Projects view for the fictional Studio Refresh project, with a saved image, note, link and task.
Search screenshot: DaBin search results for riverside, showing matching content from a fictional saved screenshot.
'''
files[C/'Creator_Outreach_Templates_UNSENT.txt']='''DABIN / OUTREACH TEMPLATES
ALL MESSAGES ARE UNSENT. No recipient has been contacted.
Use Creator_and_Publication_Targets.html to select a route; read the recipient's recent work yourself before sending. Do not claim you watched an episode, read an article or know a recipient unless you did. Fill all brackets. No mass mailing, tracking pixels, fabricated personalization or paid commitments.

01 / MAC APP CREATOR / FIRST PITCH
Subject: DaBin for Mac: save references, then search saved screenshot text

Hi [[RECIPIENT_NAME]],

Your [[SPECIFIC_ARTICLE_OR_VIDEO_TITLE_AND_URL]] covers [[ACTUAL_RELEVANT_WORKFLOW]]. I thought DaBin's save-and-find workflow might fit that topic.

DaBin is a free Apple Silicon Mac app with a little desktop robot you can drop things onto. It keeps notes, links, images, files and tasks locally. The 22-second demo uses a fictional design project, then shows finding a saved screenshot by a word inside it.

No account, ads, analytics or cloud sync. Website previews are optional and can contact manually saved sites when enabled. Requires macOS 14 or later.

App: [[APP_STORE_URL]]
Demo and facts: [[WEBSITE_URL]]

If it looks useful for your audience, you're welcome to try it and share your independent opinion. I can answer product questions; no coverage is expected.

[[DEVELOPER_NAME]]
[[CONTACT_EMAIL]]

02 / MACSTORIES / INDEPENDENT REVIEW PITCH
Subject: DaBin: a local Mac capture board with a desktop robot

Hi [[MACSTORIES_EDITOR_NAME]],

DaBin is a free Mac app for keeping useful notes, links, images, files and tasks together locally. It runs on Apple Silicon Macs with macOS 14 or later.

The angle I thought might suit MacStories is a small native capture workflow: drop a reference onto the robot, keep it with a project, and find text in saved supported screenshots and documents using local recognition. Search covers DaBin's saved content. It has no account, ads, analytics or cloud sync; optional manual-link previews can contact websites.

[[ONE_SENTENCE_FROM_YOUR_OWN_READING_OF_A_RELEVANT_MACSTORIES_ARTICLE]]

The public app is here: [[APP_STORE_URL]]. A short demo and factual press kit are here: [[WEBSITE_URL]]. The examples are fictional. You're welcome to test the app and reach your own conclusions; I can answer questions about the implementation and its limits.

[[DEVELOPER_NAME]]
[[CONTACT_EMAIL]]

03 / DESIGN WORKFLOW CREATOR
Subject: A local reference-catching workflow for Mac designers

Hi [[RECIPIENT_NAME]],

In [[REAL_RECENT_POST_TITLE_AND_URL]], you showed [[SPECIFIC_DESIGN_WORKFLOW]]. DaBin may be a useful small addition when references arrive between project tasks.

It's a free Mac app that lets you drop images, save links, write notes and keep tasks with a project. The desktop robot is the drop target. Search can find words in supported content saved into DaBin, using local Apple frameworks.

A fictional 'Studio Refresh' project demonstrates it here: [[WEBSITE_URL]]. App Store: [[APP_STORE_URL]]. It requires Apple Silicon and macOS 14 or later, has no account or cloud sync, and optional manual-link previews can contact websites.

If this fits your workflow coverage, I'd be glad to answer questions. No obligation to cover it.

[[DEVELOPER_NAME]] / [[CONTACT_EMAIL]]

04 / TIDBITS / REQUIRES OWNER READING AND EDITING
Subject: PITCH: DaBin - Mac app for saving and searching local captures

Hi Adam,

DaBin is a free Apple Silicon Mac app for saving screenshots, links, files, notes and tasks in a local board. It requires macOS 14 or later.

Its distinguishing interaction is a desktop robot drop target paired with project resources and local text search of saved supported screenshots and documents. The short example saves a fictional screenshot with a neutral filename, then finds a word inside it. It does not scan the whole Mac or use an external AI service.

[[ADD_A_SHORT_SPECIFIC_REASON_FROM_YOUR_OWN_READING_OF_TIDBITS_AND_EXPLAIN_WHY_THE_WORKFLOW_IS_DISTINCT_ENOUGH_TO_COVER]]

Public app: [[APP_STORE_URL]]
Product/support/privacy details: [[WEBSITE_URL]]

There is no account, advertising, analytics or cloud sync. Optional manual-link previews contact websites when enabled. I can answer questions about capture permissions, local storage and the limits of recognition.

[[DEVELOPER_NAME]]
[[CONTACT_EMAIL]]

Do not send the press release to TidBITS. The publisher asks for individually considered pitches and a real conversation with the developer. Read the linked pitching guide yourself and rewrite this in your own words.

05 / ONE FOLLOW-UP / SAME THREAD / ABOUT A WEEK LATER
Hi [[RECIPIENT_NAME]],

One useful detail I left out: [[ONE_NEW_VERIFIED_DETAIL_RELEVANT_TO_THEIR_AUDIENCE]]. Here's the short demo: [[WEBSITE_URL]].

If DaBin isn't a fit, no problem. I'll leave it here.

[[DEVELOPER_NAME]]

Send once only where appropriate; stop after no reply or a decline. Do not follow up on a route whose policy rejects app pitches.

06 / OPTIONAL PAID PARTNERSHIP INQUIRY / NO COMMITMENT
Subject: DaBin for Mac - fit and rates for a practical workflow demo

Hi [[RECIPIENT_OR_TEAM]],

I'm considering a small, capped marketing experiment for DaBin, a free Mac app for saving project references locally. The demo angle is finding a word inside a saved screenshot. It requires Apple Silicon + macOS 14 or later.

Would this be a fit for your [[OFFICIAL_FORMAT]]? Please share current rates, deliverables, usage rights, disclosure policy and the measurement you can provide.

App: [[APP_STORE_URL]]
Demo: [[WEBSITE_URL]]

This is an inquiry, not a booking. I'll review the fit and budget before any commitment.

[[DEVELOPER_NAME]] / [[CONTACT_EMAIL]]

Do not send unless the owner chooses a paid experiment. No pricing, guaranteed review, audience size or result has been assumed.
'''
files[C/'Apple_Featuring_Nomination_DRAFT.txt']='''DABIN / APPLE FEATURING NOMINATION
LOCAL DRAFT. Not submitted. Map this prose into the current App Store Connect form; field labels and limits may change.

NOMINATION NAME
DaBin for Mac - a local home for useful captures

TYPE
App Launch, if the first publication is still ahead.
If already public: App Enhancements only for an actual significant future update, with its real features and date. Do not backdate a launch or invent upcoming features.

PLATFORM
macOS. Apple Silicon; minimum macOS 14.

PUBLICATION WINDOW
[[ACTUAL_LAUNCH_DATE_OR_RANGE]]
Apple recommends plans be submitted as early as possible with at least three weeks' lead time. Choose an accurate future window when practical. Nomination does not guarantee featuring.

DESCRIPTION
DaBin gives useful notes, links, images, files and tasks a local place on a Mac. The app pairs a small desktop robot drop target with a native board for quick capture, project resources and deliberate task focus.

A typical example is a design project: save a reference image, a link and a note, keep them with the project, then search a word inside a saved screenshot. Local Apple frameworks recognize text in supported saved images and documents; search covers DaBin's saved content rather than the whole Mac.

DaBin is intended to launch free, with no account, advertising, analytics or cloud sync. Auto Capture starts off and offers independent clipboard and user-selected screenshot-folder controls. Optional website previews are off by default and can contact manually saved sites when enabled. The approach is useful for people who want to collect project material without creating a service account.

The launch materials show the real Mac interface with fictional examples and a separate playful robot brand film. The app supports light/dark appearance, configurable global shortcuts and macOS Reduce Motion behavior. Accessibility claims and labels will be limited to what has been evaluated on the exact distributed build.

[[ADD_ONLY_ACTUAL_RELEASE_OR_TEAM_DETAILS_THE_OWNER_WANTS_APPLE_TO_CONSIDER]]

HELPFUL DETAILS
- Audience: designers and independent creative professionals first; students and developers can use the same saved-content workflow.
- Native Mac interaction: menu-bar/desktop access, paste/drop capture, keyboard search, project organization and task focus.
- Local recognition: supported saved content; no external AI/OCR service.
- All review examples are fictional; no login or paid unlock is required in the reviewed source.
- No user numbers, performance claim, award, founder story or guaranteed accessibility support is asserted.

SUPPLEMENTAL MATERIALS (UP TO CURRENT FORM LIMIT)
[[WEBSITE_URL]]
[[APP_STORE_URL]] when public
[[PUBLIC_SUPPORT_URL]]
[[PUBLIC_DEMO_URL]]
Only provide actually accessible URLs. The local ZIP and local file paths are not valid supplemental public URLs. Do not include private account contacts in the public press kit.

REGIONS / LOCALIZATIONS
[[ACTUAL_RELEASE_TERRITORIES]]
[[ACTUAL_SHIPPED_LOCALIZATIONS]]
Do not copy the whole-world or English-only assumptions from this draft without checking the release settings.

OWNER COMPLETION
Confirm build, price, dates, territories, rights, contact and accessibility evidence. Save as Draft if facts are still pending. Submit only after deliberate final review. This package has not accessed or changed App Store Connect.

SOURCE
https://developer.apple.com/help/app-store-connect/manage-featuring-nominations/nominate-your-app-for-featuring/
Checked 4 October 2026.
'''
files[C/'Press_Release_AFTER_PUBLICATION.txt']='''DABIN / PRESS RELEASE
CONDITIONAL DRAFT: RELEASE ONLY AFTER VERIFIED PUBLICATION.
Replace every bracketed field. No press release has been distributed.

HEADLINE
DaBin launches as a free local Mac app for saving and finding useful bits

SUBHEAD
A desktop robot drop target brings notes, links, images, files and tasks into a local capture board.

[[LAUNCH_DATE]] - DaBin is now available free on the Mac App Store for Apple Silicon Macs running macOS 14 or later. It helps people save useful content during the day, keep related items with a project, and find it again on their Mac.

DaBin accepts pasted content, dropped files, notes and tasks. A small desktop robot offers a visible place to drop a reference; the board provides Inbox, Today and Projects views. Users can keep project resources together and plan tasks with a focus timer.

Local text recognition helps search find words in supported screenshots, images and documents saved into DaBin, even when the filename does not contain the query. Search covers saved DaBin content, not every file on the Mac. Recognition uses local Apple frameworks rather than an external AI service.

DaBin has no account, advertising, analytics or cloud sync. Auto Capture is optional and off by default, with independent clipboard and selected screenshot-folder controls. Website previews are also optional and off by default; enabling them can contact manually saved websites. Automatically captured links do not fetch previews.

The launch demonstrations use fictional project content. An animated 'Feed DaBin' introduction presents the robot, while actual screenshots show the app interface. The product is designed for local individual use and does not provide a shared cloud workspace.

Availability
Free on the Mac App Store: [[APP_STORE_URL]]
Requires Apple Silicon and macOS 14 or later.
Available territories: [[CONFIRMED_TERRITORIES_OR_REMOVE_THIS_LINE]]

About DaBin
DaBin is a little robot for the useful bits of your day. It keeps notes, links, images, files and tasks together on a Mac, with quick capture, project organization and local search.

Media contact
[[DEVELOPER_NAME]]
[[CONTACT_EMAIL]]
Website and press assets: [[WEBSITE_URL]]

No founder quote, motivation, user count, endorsement or future roadmap is included. Add those only with verified owner-provided facts. Do not send this release to publications whose policy rejects press releases, including TidBITS.
'''
files[C/'Product_Factsheet.txt']='''DABIN / PRODUCT FACTSHEET
Prepared 4 October 2026. Public-release fields must be completed.

Product name: DaBin
One-line description: A little robot for the useful bits of your day.
Category: Productivity
Price: Free (intended launch price per owner; confirm live listing)
Platform: macOS
Compatibility: Apple Silicon Macs; macOS 14 or later
Source candidate: 0.4.31 (86); current public version: [[PUBLIC_VERSION]]
Publication date: [[LAUNCH_DATE]]
App Store: [[APP_STORE_URL]]
Website: [[WEBSITE_URL]]
Support / media contact: [[CONTACT_EMAIL]]
Developer / rights holder: [[OWNER_CONFIRMED_PUBLIC_NAME]]

CORE WORKFLOW
Capture: Paste text or a link, drop a file/image, or create a note/task.
Organize: Keep related resources and tasks with a project; organizing is optional.
Find: Search supported content saved into DaBin, including recognized text in supported screenshots/images/documents.
Focus: Plan work and start a focus timer. A robot alarm appears at timer end; dismissing it does not complete the task.

VIEWS
Inbox: Quick captures, to-organize items and day/week capture history.
Today: Deliberate workday planning.
Projects: Resources, notes, saved items, snippets and tasks.

PRIVACY / NETWORK
No account, advertising, analytics, cloud sync or external AI/OCR service.
Saved captures and recognized text are kept on this Mac.
Auto Capture is optional and off by default; clipboard and selected screenshot-folder channels are independent. New content after activation is eligible; it does not record the live screen.
Website previews are optional and off by default. Enabled previews may contact manually saved websites; automatic-link captures do not fetch previews.
The archive is not separately encrypted by DaBin. User-chosen exports and backups may be stored in locations synced by other services.
Mac App Store builds receive updates through the App Store.

DOES NOT CLAIM
Whole-Mac search, semantic AI answers, team/cloud workspace, Intel compatibility, cross-device sync, secure forensic deletion, guaranteed sensitive-content filtering, measured time savings, Apple featuring or permanent free pricing.

MEDIA IN THIS KIT
Actual app screenshots: 03_Graphics (see graphic manifest for exact files).
Brand animation: 04_Video/DABIN__FEED_DABIN__LANDSCAPE.mp4
Portrait brand animation: 04_Video/DABIN__FEED_DABIN__PORTRAIT.mp4
Muted viewing: 04_Video/DABIN__FEED_DABIN__LANDSCAPE_SILENT.mp4
Subtitle sidecar: 04_Video/DABIN__FEED_DABIN__SUBTITLES.srt
Landing page review draft: 05_Landing_Page
The animated film is a marketing introduction, not a certified App Store preview. All sample content is fictional. No KARI material is included.
'''
files[C/'App_Store_Listing_Copy.txt']='''DABIN / APP STORE LISTING COPY
Review-ready marketing copy. Derived from the existing submission pack 0.4.31 (86), not uploaded or submitted. Compare with the final distributed build and current App Store Connect field limits. Legal/support/review fields remain in the source submission pack.

NAME (5 / 30)
DaBin

SUBTITLE (24 / 30)
Save, organize and focus

PROMOTIONAL TEXT (149 / 170)
A little robot for the useful bits of your day. Save ideas, links and files, keep projects together, and give one task your attention - all on your Mac.

DESCRIPTION
DaBin keeps the useful bits of your day together on your Mac: notes, links, images, files and tasks.

Save and find
Paste content, drop files, or create a note or task. Search your saved content across DaBin and browse results in date columns. Local text recognition helps find words in supported images and documents. Search covers content saved into DaBin, not every file on your Mac.

Organize your projects
Keep related captures and tasks in projects with recognizable colors. Preview saved content, add notes, use priority tags and export project material to a location you choose.

Focus on a task
Plan your day and choose a focus duration. When a running timer finishes, the little desktop robot shows an alarm with the first three words of your task title. Click the robot to dismiss it; the task stays open until you complete it.

Optional Auto Capture
Auto Capture starts off. After you enable it, DaBin can save later clipboard changes and new images from a screenshot folder you select. It does not record your screen or import existing screenshots. Choose a destination and pause at any time. A red recording symbol in the menu bar shows active monitoring. App exclusions and sensitive-clipboard checks help reduce unwanted captures, but cannot guarantee that all sensitive content is detected.

Local by design
No account, advertising, analytics or cloud sync. Saved captures, notes and recognized text stay on this Mac. Website previews are optional and off by default; enabling them can contact manually saved websites. Automatically captured links never fetch previews. You control exports, local backups, Recently Deleted and permanent deletion.

Made for Apple Silicon Macs with macOS 14 or later.

KEYWORDS (verify actual count below before use)
clipboard,screenshots,notes,files,tasks,projects,focus,reminders,organizer,local,robot

MARKETING URL
[[WEBSITE_URL]]

SUPPORT URL
[[PUBLIC_SUPPORT_URL]]

COPY NOTES
The description deliberately omits specific pricing; Apple shows price separately and advises against prices in descriptions. Promotional text is not keyword ranking text. Do not add competing app names to keywords. What's New is for a subsequent version only; the kit does not invent an update.

SOURCE
https://developer.apple.com/app-store/product-page/
Checked 4 October 2026.
'''
files[C/'Screenshot_Captions_and_Order.txt']='''DABIN / SCREENSHOT CAPTIONS AND ORDER
Outcome-led captions for a marketing treatment of real app screenshots. Source submission-pack-0.4.31-86 contains original 1440 x 900 native PNGs for Inbox, Projects and Focus. The exact approved upload originals remain in the submission pack. Verify modified marketing treatments and app preview assets against Apple's current Mac specifications and the shipping app before upload.

FIRST THREE / MATCH CURRENT REAL SCREENS
01 Inbox
Headline: Catch the useful bits.
Support: Save notes, links, images and files on your Mac.
Show: readable fictional captures; the primary interface is visible and unobscured.
Source: DABIN__APP_STORE__01_INBOX.png

02 Projects
Headline: Keep a project together.
Support: References, notes and tasks in one local workspace.
Show: fictional project title and distinct resource previews.
Source: DABIN__APP_STORE__02_PROJECTS.png

03 Focus
Headline: Give one task your attention.
Support: Plan your day and choose a focus duration.
Show: the actual Today/Focus controls and a task; do not depict task completion merely from timer expiry.
Source: DABIN__APP_STORE__03_FOCUS.png

ADDITIONAL REAL CAPTURE TO MAKE WHEN PUBLIC BUILD IS READY
04 Saved-content Search
Headline: Find words inside saved screenshots.
Support: Local text search for supported content you've saved.
Show: query 'terracotta', fictional screenshot with that word, neutral filename and matching result line. Do not put the word in the filename/title/caption as the only proof of OCR. Show actual successful search, not a composed mockup presented as real UI.
Proposed output: DABIN__APP_STORE__04_SEARCH.png
This kit does not assert that this extra screenshot has been captured or approved unless its asset manifest records it.

OPTIONAL ADDITION
05 Local controls / Settings
Headline: Your Mac. Your useful bits.
Support: No account, ads, analytics or cloud sync.
Show: actual settings and clear off-by-default Auto Capture/website-preview controls. Explain optional network previews in adjacent listing copy; avoid '100% offline' or 'nothing leaves your Mac'.
Proposed output: DABIN__APP_STORE__05_LOCAL_CONTROLS.png

DESIGN RULES
One benefit per image. Keep interface text readable at normal viewing size. Avoid busy feature grids, tiny captions or a robot blocking important UI. Use a consistent margin and headline position. Do not add Apple featuring/award badges or an unofficial App Store badge. Include a dark appearance image if it truthfully shows the shipping UI and adds value.

APP PREVIEW VIDEO
The supplied Blender Feed DaBin film is for social/website/press. Apple says app previews use footage captured on the device to demonstrate the app. Make a separate native capture if an App Store preview is wanted, then verify Mac dimensions, length and other requirements. Do not upload the brand animation unchanged as a certified preview.

SOURCE
https://developer.apple.com/app-store/product-page/
https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/
'''
files[C/'Landing_Page_Copy.txt']='''DABIN / LANDING PAGE COPY
Use this to review the local 05_Landing_Page draft. Replace placeholders before deployment. Nothing is hosted by this kit.

PAGE TITLE
DaBin for Mac - Save now. Find it later.

META DESCRIPTION
DaBin is a free Mac app for keeping notes, links, images, files and tasks together locally. Save useful bits with a little desktop robot. Apple Silicon, macOS 14+.

HERO
Eyebrow: DaBin for Mac
Headline: Save now. Find it later.
Subheadline: A little robot for the useful bits of your day. Keep notes, links, images, files and tasks together on your Mac.
Primary action: Get DaBin free
Destination: [[APP_STORE_URL]]
Compatibility line: Apple Silicon Macs. macOS 14 or later. No account required.
Hero media: 04_Video/DABIN__FEED_DABIN__LANDSCAPE.mp4
Media label where context is needed: An animated introduction to DaBin; real app views below.

BENEFIT 1
Catch the useful bits.
Drop a reference image, paste a link, or write a note. Give useful things a place while you keep working.

BENEFIT 2
Find words inside saved screenshots.
Search the supported content you've saved into DaBin. Local text recognition helps find a screenshot or document even when its filename doesn't contain the word.

BENEFIT 3
Keep a project together.
Keep a project's references, notes and tasks close. Organization is optional; save first and sort when it helps.

PRIVACY
Local by design.
No account, ads, analytics or cloud sync. Saved captures and recognized text stay on this Mac. Auto Capture is optional and off by default. Website previews are also optional and off by default; enabling them can contact manually saved sites.
Read privacy details: [[PUBLIC_PRIVACY_URL]]

FINAL CTA
Give the useful bits a home.
Get DaBin free: [[APP_STORE_URL]]
Apple Silicon + macOS 14 or later.

FAQ
What Macs can run it?
Apple Silicon Macs with macOS 14 or later.

Does it search my whole Mac?
No. Search covers supported content saved into DaBin, including recognized text in supported screenshots, images and documents.

Do I need an account?
No. There is no account or cloud sync.

Does it automatically watch my clipboard or screenshots?
Only if you opt into Auto Capture. Clipboard and a selected screenshot folder are separate options, off by default. Monitoring considers later clipboard changes and new images after activation; it does not record your screen or import old screenshots.

Can it contact websites?
Optional previews for manually saved links can contact websites when enabled. Previews start off, and automatically captured links do not fetch previews. Opening a link uses your browser.

How do I get help?
Contact [[CONTACT_EMAIL]] or visit [[PUBLIC_SUPPORT_URL]].

FOOTER
DaBin for Mac
Support: [[PUBLIC_SUPPORT_URL]]
Privacy: [[PUBLIC_PRIVACY_URL]]
Contact: [[CONTACT_EMAIL]]
Copyright: [[OWNER_CONFIRMED_COPYRIGHT]]

DO NOT ADD WITHOUT FACTS
Founder origin story, 'trusted by' logos, testimonials, download count, 'free forever', future roadmap, Apple featuring badge, encrypted-data claims or quantified time savings.
'''
files[C/'Video_Scripts_and_Shotlist.txt']='''DABIN / THREE DEMO BRIEFS
The produced 22-second Feed DaBin film has its exact voice script and timing in 04_Video. This file is an editable brief for follow-up real-app captures. Check final subtitles against the actual spoken audio.

A / FEED DABIN / 22 SECOND BRAND INTRODUCTION
Aim: make the robot memorable and connect it to saving and finding useful content.
0-3s: DaBin robot arrives; text 'Feed DaBin the useful bits.'
3-9s: clearly fictional image, link and note move into the robot/capture board. Animated interaction may be stylized.
9-14s: actual app screenshot or native recording shows a fictional project and saved items; distinguish real interface from brand animation.
14-17s: show finding a saved item; only depict OCR search if it is a real verified search recording.
17-20s: 'Save now. Find it later. Keep it on your Mac.' Then 'Free for Apple Silicon Macs. macOS 14+.' Use a real download link in the surrounding post/website once public.
Suggested voice wording, subject to the final produced script: 'Meet DaBin, a little robot for the useful bits of your day. Drop in a link, an image or a note. Keep them with a project and find them again. Free for Mac. No account required.'
Final: 04_Video/DABIN__FEED_DABIN__LANDSCAPE.mp4
Social: 04_Video/DABIN__FEED_DABIN__PORTRAIT.mp4
Silent: 04_Video/DABIN__FEED_DABIN__LANDSCAPE_SILENT.mp4
Sidecar: 04_Video/DABIN__FEED_DABIN__SUBTITLES.srt

B / WHERE DID THAT SCREENSHOT GO? / 15-20 SECOND NATIVE CAPTURE
Create a fictional screenshot containing 'terracotta' within readable design-note content. Save with neutral filename 'reference_03.png'; don't put the query in its title or comment. Manually save into DaBin. Confirm recognized text and the actual result before recording.
0-3s: show fictional screenshot and the question 'Where did that screenshot go?'
3-7s: save it into DaBin using real app controls.
7-13s: open Search, type 'terracotta', show actual result and matching line.
13-17s: open the result; on-screen 'Find words in saved screenshots. Recognition runs on your Mac.'
17-20s: 'Get DaBin free. Apple Silicon + macOS 14 or later.'
Suggested voice: 'Saved a screenshot and forgot its name? Save it in DaBin, then search a word inside it. Text recognition runs on your Mac, across supported content you've saved. DaBin is free. No account required.'
Status: follow-up recording brief; not represented as produced footage by this file.

C / ONE PROJECT, USEFUL BITS TOGETHER / 20-30 SECOND NATIVE CAPTURE
Use fictional 'Studio Refresh' project: sample image, example.com design link, 'Try the warmer palette' note and 'Review palette' task.
0-4s: 'A useful reference always arrives at the wrong time.'
4-13s: save three items through actual paste/drop/note actions.
13-21s: show the project resources and next task, with readable real UI.
21-26s: open the saved reference again; 'Keep a project's useful bits together.'
26-30s: download CTA + compatibility.
Suggested voice: 'A reference image, a useful link, and one idea for later. Keep them with a project in DaBin, beside the next task. Save while you're working. Find it when you need it. Free for Mac.'
Status: follow-up recording brief.

PRODUCTION
Fictional sample content only. Hide notifications/personal desktop/clipboard. Keep sound-off meaning complete with readable text. Use accurate subtitles; do not advertise a silent clip as voiced. Keep a clean ending instead of a tiny URL unreadable at social size. For actual App Store previews, use device-captured footage and a separate Apple-specification check.
'''
files[C/'Support_and_Reply_Copy.txt']='''DABIN / SUPPORT & COMMUNITY REPLIES
UNSENT. Adapt to the actual question. Do not claim to have fixed a problem unless verified.

IS IT FREE?
DaBin is free on the Mac App Store: [[APP_STORE_URL]]. Requires Apple Silicon and macOS 14 or later. [Use only after Free pricing and publication are verified.]

WHY IS IT FREE?
[[OWNER_PROVIDED_REASON]]
No founder motivation or future business model was provided for this kit. Until there is an owner answer, keep it factual: 'DaBin is free in the current listing, with no account, ads or paid unlock in this build.' Do not promise permanent pricing.

WHICH MACS?
Apple Silicon Macs with macOS 14 or later. The current release does not provide Intel, Windows or iPhone support.

IS THE ROBOT AI?
The robot is the app's desktop companion and drop target. DaBin uses local text recognition to help search supported content you've saved; it doesn't answer questions with an AI model.

WHERE DOES MY CONTENT GO?
DaBin keeps saved captures, notes and recognized text on this Mac. It has no account, ads, analytics or cloud sync. Optional previews can contact manually saved websites when enabled. Exports and backups go where you choose; a synced folder may be uploaded by its own service.

DOES IT SEARCH ALL MY FILES?
It searches supported content saved into DaBin, not every file on your Mac. If recognition misses text, you can inspect the recognized text in the saved capture and rebuild the local index in Settings. Very large documents may be partially indexed.

DOES IT WATCH MY SCREEN?
Auto Capture is off by default. You can separately enable clipboard monitoring and a screenshot folder you choose. It considers later clipboard changes/new images; it does not record the live screen or import existing screenshots.

IS DATA ENCRYPTED?
DaBin's archive is not separately encrypted by the app. Your Mac's account access and disk protection apply. The privacy policy explains local storage, deletion and backups: [[PUBLIC_PRIVACY_URL]].

CAN I SYNC OR SHARE A TEAM WORKSPACE?
The current app stores content locally and has no cloud sync or shared team workspace. You can export content to a location you choose.

BUG REPORT
Thanks for explaining the issue. Please share your macOS version, DaBin version and the steps that caused it at [[CONTACT_EMAIL]]. Use fictional sample content and don't send your personal capture archive. [[ONLY_ADD_VERIFIED_WORKAROUND_IF_ONE_EXISTS]]

VOLUNTARY FIRST-USE QUESTION
If you'd like to share feedback: what kind of thing did you save first, and could you find it again? Please describe the workflow rather than sending the actual private content.

WHEN FEATURE REQUESTS ARRIVE
Thanks - I understand the use case. The current version supports [[VERIFIED_CURRENT_BEHAVIOR]]. I haven't announced [[REQUESTED_FEATURE]]; I'll keep your request in mind. [Do not promise a date or roadmap that doesn't exist.]
'''
for path,content in files.items(): path.write_text(content.strip()+'\n',encoding='utf-8')
# Exact listing lengths, corrected automatically in notes.
listing=C/'App_Store_Listing_Copy.txt'
x=listing.read_text(); subtitle='Save, organize and focus'; promo='A little robot for the useful bits of your day. Save ideas, links and files, keep projects together, and give one task your attention - all on your Mac.'; keywords='clipboard,screenshots,notes,files,tasks,projects,focus,reminders,organizer,local,robot'
x=x.replace('SUBTITLE (24 / 30)',f'SUBTITLE ({len(subtitle)} / 30)').replace('PROMOTIONAL TEXT (149 / 170)',f'PROMOTIONAL TEXT ({len(promo)} / 170)').replace('KEYWORDS (verify actual count below before use)',f'KEYWORDS ({len(keywords)} / 100)'); listing.write_text(x)
# 30 real operational actions; launch-relative, no invented date.
actions=[
('Launch','Verify the live App Store listing, Free price and supported territories. Publish the landing page and one feed-film social announcement.','Feed film + Launch post','Actual public availability and working links','45 min'),
('Launch','Publish one r/macapps post if current rules and account eligibility are met. Reply to questions.','Reddit_MacApps_Post.txt','Required disclosure, changelog and promotion timing completed','40 min'),
('Launch','Read recent work from three relevant targets; send individually tailored pitches if chosen by the owner.','Creator target shortlist + unsent template','Real relevance sentence and final live links','45 min'),
('Launch','Check App Store Connect for campaign-link availability and record the first baseline. Keep unavailable values blank.','Campaign_Measurement.txt','Live download data; real Apple-generated links','30 min'),
('Launch','Publish the designer project-reference example and answer one workflow question.','Designer post + Projects graphic','Actual UI with fictional Studio Refresh data','30 min'),
('Launch','Prepare the Product Hunt gallery and maker comment; choose a staffed publication day.','Product_Hunt_Copy.txt','Working app/site/support and accurate screenshots','45 min'),
('Review','Review week one: support questions, channel reach, available downloads and outreach responses.','campaign-tracker.json','Comparable date ranges; no inferred retention','45 min'),
('Search','Record or finish the real saved-screenshot text-search demo using a neutral filename.','Video_Scripts_and_Shotlist.txt / Brief B','Word appears in saved image and actual search result','45 min'),
('Search','Publish screenshot-search demo with one clear benefit and compatibility.','Search social post + real demo','No whole-Mac or semantic search claim','25 min'),
('Search','Tailor pitches to two more relevant targets, leading with the saved-screenshot workflow.','Outreach template 01 or 03','Read recipient work and route policy','40 min'),
('Community','Launch on Product Hunt if ready and stay available for questions; otherwise keep it in draft.','PH listing + maker comment','No upvote request; truthful personal maker identity','45 min + replies'),
('Community','Answer compatibility and local-storage questions; update public FAQ if needed.','Support_and_Reply_Copy.txt','Actual question or verified explanation','25 min'),
('Community','One short follow-up to first-week pitches where appropriate, with a new relevant detail.','Outreach template 05','About a week elapsed; no decline/policy exclusion','20 min'),
('Review','Compare the capture and search hooks using observed metrics and qualitative replies.','Tracker + weekly review','Matching reporting window and metric scope','45 min'),
('Audience test','Prepare the student use case with fictional course notes and one saved screenshot.','Student social copy','Actual saved-content workflow, no study-outcome promise','35 min'),
('Audience test','Publish the student test on one suitable existing channel.','Student post + real example','Compatibility and searchable-saved-content limit','25 min'),
('Outreach','Read recent work and tailor pitches to two more relevant publication/creator routes.','Targets + outreach template','No claim of prior familiarity without reading','40 min'),
('How-to','Publish a short answer to a real common question, or a factual local-search explainer.','Support reply + short clip/card','Only call it common if evidence exists','30 min'),
('Audience test','Prepare the developer example: documentation link, saved snippet and next task.','Developer social copy','No integration or code-execution claim','35 min'),
('Audience test','Publish the developer example; ask for optional workflow feedback.','Developer post + real project view','No request for private saved files','25 min'),
('Review','Review audience response and shortlist remaining targets. Select the strongest observed angle.','Weekly review + tracker','Avoid conclusions from withheld metrics','45 min'),
('Outreach','Send up to three final high-fit organic pitches if the owner chooses; reach ten total only if appropriate.','Tailored unsent templates','Route policy, real fit and no bulk send','45 min'),
('Project','Publish the one-project demo showing references, a note and the next task.','Video_Scripts_and_Shotlist.txt / Brief C','Actual app view, fictional examples','25 min'),
('Follow-up','Follow up once on second-week outreach where welcome; log replies or declines.','Outreach template 05','Same thread; one follow-up maximum','20 min'),
('Proof','Share actual independent coverage with a short accurate description if any exists; otherwise publish a useful tip.','Coverage follow-up social draft','Actual coverage URL; no fabricated endorsement','25 min'),
('Clarity','Check website/product-page questions and improve one unclear caption or FAQ answer.','Landing/Screenshot copy','Current shipping behavior; no unsupported new promise','35 min'),
('Planning','Review Apple nomination draft for a real future release or enhancement; keep dates truthful.','Apple_Featuring_Nomination_DRAFT.txt','Real feature/date and lead time where practical','30 min'),
('Review','Review all campaign/date-range data and time spent; keep missing data explicit.','campaign-tracker.json','Apple threshold/attribution limits recorded','45 min'),
('Refresh','Refresh the strongest demo with a new fictional example or verified answer; do not repeat a subreddit promotion early.','Best-performing supported message','Current platform rules and public build','30 min'),
('Decision','Write a month-end observation note and choose one audience, one hook and next month\'s two demos.','Monthly decision note','Observed facts only; optional paid spend requires budget decision','45 min')]
cal={'schemaVersion':1,'prepared':'2026-10-04','status':'LOCAL_PLAN_NOT_SCHEDULED','day1Definition':'The day DaBin is verified publicly downloadable on the Mac App Store in the intended territories.','launchDate':None,'timezone':'Set the publication timezone explicitly when dates are assigned.','prelaunch':[{'offset':-21,'action':'Nominate the actual launch for Apple featuring where practical; Apple recommends at least three weeks lead time.'},{'offset':-7,'action':'Finish live-link fields, support/privacy routes, final-build comparison and fictional sample media.'},{'offset':-1,'action':'Watch final exports, check captions/crops, reread platform rules and prepare a staffed launch.'}],'days':[{'day':i+1,'phase':a[0],'action':a[1],'asset':a[2],'completionEvidence':a[3],'suggestedEffort':a[4],'status':'planned','actualDate':None,'notes':''} for i,a in enumerate(actions)]}
(P/'30_Day_Calendar.json').write_text(json.dumps(cal,indent=2)+'\n')
tracker={'schemaVersion':1,'status':'EMPTY_MEASUREMENT_TEMPLATE','launchDate':None,'note':'No results have been collected. null means unavailable/not entered, never zero. No in-app analytics is added or assumed.','proposedCampaignTokens':['feed_social_launch','screenshot_search_social','reddit_macapps_launch','producthunt_launch','website_main','creator_shortname'],'records':[],'recordTemplate':{'date':None,'channel':'','audience':'','asset':'','campaignToken':'','appleGeneratedURL':'','publicationURL':'','reportingStart':None,'reportingEnd':None,'minutesSpent':None,'platformViews':None,'platformClicks':None,'appStoreProductPageViews':None,'firstTimeDownloads':None,'outreachReplies':None,'coverageURL':'','voluntaryFeedbackSummary':'','metricAvailability':'not entered','attributionNotes':'','nextDecision':''}}
(P/'campaign-tracker.json').write_text(json.dumps(tracker,indent=2)+'\n')
# Verified route table; inference is separated from what each official site says.
targets=[
{'name':'MacStories','priority':'1 / organic editorial','route':'Official team email links on About page','url':'https://www.macstories.net/about/','fit':'Native Mac workflow, project references and local recognition.','opening':'MacStories focuses on detailed app testing; offer the public build, factual limits and a short demo.','policy':'Independent review only; the site says it does not do paid reviews. Read recent relevant coverage yourself.'},
{'name':'The Sweet Setup','priority':'1 / organic inquiry','route':'Contact-page email link or official social account','url':'https://thesweetsetup.com/contact/','fit':'Keeping creative ideas and project references together.','opening':'Lead with one calm capture-to-project workflow rather than the robot alone.','policy':'Contact route welcomes feedback/questions; advertising has a separate sponsorship route. No coverage acceptance is assumed.'},
{'name':'The Mac Observer','priority':'1 / organic editorial','route':'Contact us form; subject Suggestion for an article','url':'https://www.macobserver.com/contact/','fit':'A practical free Mac app with a distinct save/find interaction.','opening':'Give the public app link and a concrete local saved-screenshot search example.','policy':'Use the general/editorial form rather than advertising unless a paid inquiry is intended.'},
{'name':'TidBITS','priority':'1 / individually considered pitch','route':'Publisher contact on official Contact page','url':'https://tidbits.com/about/contact/','fit':'Local Apple-platform utility; needs a clear distinction from a crowded capture category.','opening':'PITCH: DaBin - Mac app for saving and searching local captures. Read the publisher\'s app-pitch article yourself.','policy':'No press releases, guest/sponsored posts or link insertions. Send a concise, personally edited pitch; do not claim research you have not done.','extra':'https://tidbits.com/2026/07/23/how-to-pitch-apps-to-tidbits-in-the-ai-era/'},
{'name':'Created Tech','priority':'2 / organic inquiry','route':'Official contact form','url':'https://createdtech.com/contact','fit':'Design/Apple workflow; current official site includes Figma and image-editing guides.','opening':'Offer the fictional Studio Refresh project-reference workflow and real interface views.','policy':'Contact form verified. Check current coverage/activity and policy before sending; some visible articles are older. No response or review is assumed.'},
{'name':'9to5Mac','priority':'2 / organic newsroom pitch','route':'News Tips email link on official Contact page','url':'https://9to5mac.com/contact/','fit':'Mac app launch and native/local design details.','opening':'Lead with the Mac app\'s concrete capture/search behavior and a downloadable public build.','policy':'Use News Tips, not advertising, for an editorial pitch. The form says tips may be published/syndicated; provide only public information.'},
{'name':'MacRumors','priority':'2 / organic newsroom pitch','route':'Official tips address on About page','url':'https://www.macrumors.com/about/','fit':'Potential small Mac-app roundup or practical software discovery.','opening':'Concise facts: free, Apple Silicon/macOS 14+, local saved-content text recognition and desktop drop target.','policy':'Official general tips route verified. Interest and coverage are uncertain; avoid a generic oversized press-release attachment.'},
{'name':'MacSparky / David Sparks','priority':'2 / short editorial note','route':'To Reach David address on current About page','url':'https://www.macsparky.com/about/','fit':'Practical Apple productivity and keyboard capture/project workflow.','opening':'Use a clear subject and one real workflow; do not pitch a podcast guest or paid link deal.','policy':'About page provides a general address and warns replies are limited. Sponsorship is separate; listed availability on its sponsorship page may be stale.'},
{'name':'Better Creating','priority':'3 / optional partnership inquiry','route':'Official partnerships form/email','url':'https://bettercreating.com/partnerships','fit':'Intentional technology and creative/productive software.','opening':'A design-reference workflow that shows a useful outcome with a small, clearly scoped demo.','policy':'The official page offers sponsorship/product features/reviews. Rates and whether coverage is paid must be clarified. No booking or budget is approved by this kit.'},
{'name':'Jeff Su','priority':'3 / optional paid partnership inquiry','route':'Start a partnership link on official Partnerships page','url':'https://www.jeffsu.org/partnerships/','fit':'Working professionals collecting references and next actions.','opening':'A specific save/find workflow; ask for fit, rates, deliverables and measurement if the owner chooses a paid test.','policy':'Official route is a partnership intake with scoped rates; do not treat it as guaranteed free editorial coverage.'}
]
(P/'creator-targets.json').write_text(json.dumps({'prepared':'2026-10-04','status':'RESEARCH_ONLY_NO_CONTACT','fitNote':'Fit and priority are our marketing judgment; routes/policies are verified on official sources. Recheck before outreach.','targets':targets,'doNotPitch':[{'name':'MacMost','url':'https://macmost.com/contact','reason':'Official page explicitly rejects product reviews, free products for review and marketing partnerships; its topic form must not be used to ask it to review or link a product.'}],'notIncluded':[{'name':'DailyTekk','reason':'Official contact page could not be fetched during this check; no route or email is guessed.'}]},indent=2)+'\n')
styles='''body{margin:0;background:#f3f0e9;color:#17212d;font:16px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}main{max-width:1100px;margin:0 auto;padding:48px 28px}header{border-top:8px solid #187f85;padding-top:26px;margin-bottom:32px}h1{font-size:clamp(32px,5vw,58px);line-height:1.1;letter-spacing:-1.5px;margin:12px 0}h2{font-size:26px;line-height:1.3;margin:30px 0 14px}h3{font-size:20px;margin:0 0 10px}p{max-width:850px}a{color:#116e75;text-underline-offset:3px}.eyebrow{font-size:12px;text-transform:uppercase;letter-spacing:2px;font-weight:800;color:#116e75}.lede{font-size:21px;line-height:1.55}.note{padding:16px 20px;background:#e6eeee;border-left:4px solid #187f85;border-radius:4px}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:18px}.card{background:white;padding:24px;border:1px solid #deded8;border-radius:16px;box-shadow:0 5px 18px #17212d05}.badge{display:inline-block;background:#e6eeee;color:#116e75;padding:3px 10px;border-radius:30px;font-size:12px;font-weight:700}.table-scroll{overflow-x:auto}table{width:100%;border-collapse:collapse;background:white;border-radius:12px;overflow:hidden}th,td{padding:15px 16px;text-align:left;vertical-align:top;border-bottom:1px solid #e7e8e2}th{background:#17212d;color:white;font-size:12px;text-transform:uppercase;letter-spacing:1px}td:first-child{font-weight:700;white-space:nowrap}footer{margin-top:44px;padding-top:20px;border-top:1px solid #d6d9d4;font-size:13px;color:#59636b}.compact{font-size:14px}code{font-size:.92em;background:#e6eeee;padding:2px 4px;border-radius:4px}ul{padding-left:22px}li{margin-bottom:7px}@media print{body{background:white;font-size:10pt}main{padding:0}header{border-top:4px solid #187f85}h1{font-size:28pt}.card{box-shadow:none;break-inside:avoid}tr{break-inside:avoid}a{color:#17212d}}'''
def page(title,body): return '<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>'+html.escape(title)+'</title><style>'+styles+'</style></head><body><main>'+body+'<footer>DaBin launch kit / Prepared 4 October 2026 / Local drafts. No posts, outreach, hosting or submissions have been made.</footer></main></body></html>'
rows=''.join(f'<tr><td>Day {d["day"]}</td><td><span class="badge">{html.escape(d["phase"])}</span><p>{html.escape(d["action"])}</p></td><td class="compact">{html.escape(d["asset"])}</td><td class="compact">{html.escape(d["completionEvidence"])}</td><td>{html.escape(d["suggestedEffort"])}</td></tr>' for d in cal['days'])
(P/'30_Day_Calendar.html').write_text(page('DaBin / 30-day launch calendar','<header><div class="eyebrow">DaBin / Launch playbook</div><h1>One useful story at a time.</h1><p class="lede">A practical 30-day plan, starting when DaBin is publicly downloadable.</p></header><p class="note"><strong>Day 1 is your verified publication date.</strong> This is a relative plan, not a scheduled automation. Move publication tasks to match actual readiness and platform rules. Keep a daily reply check during launch week.</p><h2>Before Day 1</h2><div class="grid"><div class="card"><h3>At least 3 weeks ahead</h3><p>Prepare the actual Apple featuring launch nomination where practical. Nomination is editorial consideration, not a promise.</p></div><div class="card"><h3>One week ahead</h3><p>Complete URLs, support, privacy, final-build comparison, fictional examples and current platform-rule checks.</p></div><div class="card"><h3>The day before</h3><p>Watch the final clips with sound and muted. Check crops, subtitles, compatibility and every destination link.</p></div></div><h2>The first month</h2><div class="table-scroll"><table><thead><tr><th>Day</th><th>Action</th><th>Use</th><th>Done when</th><th>Time</th></tr></thead><tbody>'+rows+'</tbody></table></div><p>Editable plan: <a href="30_Day_Calendar.json">30_Day_Calendar.json</a>. Empty results tracker: <a href="campaign-tracker.json">campaign-tracker.json</a>. Measurement limits: <a href="Campaign_Measurement.txt">Campaign_Measurement.txt</a>.</p>'),encoding='utf-8')
cards=''.join('<article class="card"><span class="badge">'+html.escape(t['priority'])+'</span><h2>'+html.escape(t['name'])+'</h2><p><strong>Suggested fit:</strong> '+html.escape(t['fit'])+'</p><p><strong>Opening angle:</strong> '+html.escape(t['opening'])+'</p><p class="compact"><strong>Verified route:</strong> <a href="'+t['url']+'">'+html.escape(t['route'])+'</a></p><p class="compact">'+html.escape(t['policy'])+'</p>'+ ('<p class="compact"><a href="'+t['extra']+'">Read the publisher\'s current pitch guidance</a></p>' if 'extra' in t else '')+'</article>' for t in targets)
(P/'Creator_and_Publication_Targets.html').write_text(page('DaBin / Creator and publication shortlist','<header><div class="eyebrow">DaBin / Outreach research</div><h1>Ten routes. A useful reason for each.</h1><p class="lede">Start with a few relevant conversations. Every contact route below comes from an official site checked on 4 October 2026.</p></header><p class="note">No one has been contacted. Fit and priority are marketing judgments, not confirmed interest. Read recent work yourself, tailor one short pitch and use only public product information. Paid routes are optional and require a budget decision.</p><div class="grid">'+cards+'</div><h2>A route to skip</h2><p><a href="https://macmost.com/contact">MacMost</a> explicitly rejects product-review and marketing requests, including free products for review. Its topic-suggestion form must not be used to ask it to review or link DaBin.</p><p>DailyTekk is omitted because its official contact page could not be fetched during this check. No personal email or contact route has been guessed.</p><p>Use <a href="../02_Copy/Creator_Outreach_Templates_UNSENT.txt">the unsent outreach drafts</a> and <a href="creator-targets.json">the editable target data</a>. Recheck route policies before sending.</p>'),encoding='utf-8')
(P/'START_HERE.html').write_text(page('DaBin / Launch playbook','<header><div class="eyebrow">DaBin / Marketing package</div><h1>Save now.<br>Find it later.</h1><p class="lede">A practical launch kit for a free local Mac app, with a little robot that gets attention and a workflow that earns the download.</p></header><p class="note"><strong>Prepared for launch; not published.</strong> Start Day 1 only when the App Store release is visible and downloadable. Replace <code>[[APP_STORE_URL]]</code>, <code>[[WEBSITE_URL]]</code>, <code>[[CONTACT_EMAIL]]</code> and owner fields before anything goes public.</p><div class="grid"><article class="card"><h3>Read the guide</h3><p>The concise launch guide explains positioning, assets, channels and measurement.</p><a href="DaBin_Launch_Guide.pdf">Open the PDF guide</a></article><article class="card"><h3>Run the month</h3><p>A launch-relative day-by-day table, with effort and completion evidence.</p><a href="30_Day_Calendar.html">Open the 30-day calendar</a></article><article class="card"><h3>Find the right people</h3><p>Ten researched routes with a concrete angle and verified contact policy.</p><a href="Creator_and_Publication_Targets.html">Open the outreach shortlist</a></article></div><h2>The first three moves</h2><ol><li>Complete the release, live links and support details in the <a href="Launch_Checklist.txt">launch checklist</a>.</li><li>Lead with the <a href="../04_Video/DABIN__FEED_DABIN__LANDSCAPE.mp4">Feed DaBin film</a>, then a real saved-screenshot search demo.</li><li>Publish one community announcement and tailor a small batch of <a href="../02_Copy/Creator_Outreach_Templates_UNSENT.txt">unsent pitches</a>.</li></ol><h2>Reference files</h2><ul><li><a href="DaBin_Launch_Strategy.txt">Strategy and audience plan</a></li><li><a href="Claim_Guardrails.txt">Messaging claim guardrails</a></li><li><a href="Campaign_Measurement.txt">Measurement routine and limits</a> / <a href="campaign-tracker.json">empty tracker</a></li><li><a href="../02_Copy/Copy_Index.html">All platform-ready copy</a></li><li><a href="Sources_and_Provenance.txt">Sources and provenance</a></li></ul><p>App Store previews need actual device-captured footage and a separate specification check. The Blender robot sequence is a social/website brand introduction. DaBin is distinct from the private KARI project; this kit uses only DaBin assets and fictional examples.</p>'),encoding='utf-8')
copylinks=''.join('<li><a href="'+p.name+'">'+p.stem.replace('_',' ')+'</a></li>' for p in sorted(C.glob('*.txt')))
(C/'Copy_Index.html').write_text(page('DaBin / Copy library','<header><div class="eyebrow">DaBin / Copy library</div><h1>Useful words.<br>Ready to adapt.</h1><p class="lede">Launch posts, pitch drafts, store copy, press material and replies in editable plain text.</p></header><p class="note">All outreach remains unsent. Publication copy is conditional on verified App Store availability. Replace every bracketed field before use, and adapt text to the live platform limits.</p><div class="card"><ul>'+copylinks+'</ul></div><p><a href="../01_Launch_Playbook/START_HERE.html">Back to launch playbook</a></p>'),encoding='utf-8')
sources='''DABIN / SOURCES AND PROVENANCE
Prepared 4 October 2026. Web sources checked on that date. Rules, contact routes and form requirements should be checked again at launch.

PRODUCT AUTHORITY
DaBin/README.md - native app workflow, local saved-content recognition, privacy and platform context. README contains older installed-version status; the source candidate is taken from the newer submission pack.
DaBin/docs/app-store/submission-pack-0.4.31-86/README.txt - prepared local content pack; no public-release/submission claim.
DaBin/docs/app-store/submission-pack-0.4.31-86/Copy/description.txt - reviewed feature/compatibility copy.
DaBin/docs/app-store/submission-pack-0.4.31-86/Copy/PrivacyPolicy.md - updated 4 October 2026; local storage, recognition and network exceptions.
DaBin/docs/app-store/submission-pack-0.4.31-86/Copy/metadata-en-US.json - source candidate 0.4.31 (86), arm64, macOS 14.0, DRAFT_NOT_FOR_UPLOAD; owner/public-release fields pending.
Source screenshots: native 1440 x 900 RGB PNGs for Inbox, Projects and Focus from the same pack. They use fictional data.
Source app icon: Assets/DaBin-App-Icon-1024.png from the same pack.
The owner states the intended product is free. Free pricing must still match the eventual live listing; no permanent pricing commitment is inferred.

PLATFORM GUIDANCE
Reddit r/macapps developer-post notice:
https://www.reddit.com/r/macapps/comments/1r6d06r/new_post_requirements_to_combat_low_quality/
Supports concise structured developer posts, developer/AI disclosure and limited self-promotion. The notice describes an experiment; current rules take priority. This kit neither posts nor selects an unverified AI category.

Product Hunt official launch guide:
https://www.producthunt.com/launch
Supports preparation, personal maker identity, own-product submission and asking for comments rather than upvotes. No hunter, placement or ranking is promised.

Apple product page guidance:
https://developer.apple.com/app-store/product-page/
Supports clear UI screenshots, outcome emphasis, device-captured app previews, concise description, subtitle/promotional/keyword limits and avoiding price/competitor-keyword claims in store metadata.

Apple screenshot specifications:
https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/
Reference for a separate check before any new treatment is uploaded. This marketing kit does not certify newly created graphics as App Store-upload compliant.

Apple featuring nomination:
https://developer.apple.com/help/app-store-connect/manage-featuring-nominations/nominate-your-app-for-featuring/
Supports nomination for actual launches/enhancements and recommends at least three weeks' lead time. Drafting here does not submit a nomination or establish editorial selection.

Apple campaign links:
https://developer.apple.com/help/app-store-connect-analytics/acquisition/campaign-links
Supports Apple-generated attribution links, delayed availability for new apps, minimum reporting thresholds and attribution limits. This plan adds no analytics to DaBin.

OFFICIAL OUTREACH SOURCES
MacStories: https://www.macstories.net/about/
The Sweet Setup: https://thesweetsetup.com/contact/
The Mac Observer: https://www.macobserver.com/contact/
TidBITS contacts: https://tidbits.com/about/contact/
TidBITS app-pitch guidance: https://tidbits.com/2026/07/23/how-to-pitch-apps-to-tidbits-in-the-ai-era/
Created Tech: https://createdtech.com/contact
Created Tech publication scope: https://createdtech.com/
9to5Mac: https://9to5mac.com/contact/
MacRumors: https://www.macrumors.com/about/
MacSparky: https://www.macsparky.com/about/
Better Creating: https://bettercreating.com/partnerships
Jeff Su: https://www.jeffsu.org/partnerships/
MacMost exclusion: https://macmost.com/contact
Each route/policy is described in Creator_and_Publication_Targets.html. Suggested fit and priority are editorial judgments, not source statements about interest in DaBin. No private emails are guessed; public addresses remain accessible on official contact pages.
DailyTekk's official contact page was unavailable to the web check, so it is not treated as a verified outreach route.

AUTHORING / STATUS
Written copy and launch plan authored locally from DaBin source material and public generic marketing guidance. No KARI screenplay, reference, prompt, image or capture archive was accessed or copied for this task. No messages have been sent, no posts published, no website hosted, no Apple forms submitted and no recurring automation created.

NOT INCLUDED AS FACTS
Founder backstory; why the product is free; public launch date; actual App Store URL; public contact email; user numbers; endorsements; permanent pricing; measured retention/activation; future roadmap; full accessibility evaluation. Explicit fields or conditional drafts are used where owner facts are needed.
'''
(P/'Sources_and_Provenance.txt').write_text(sources)
print('Written files:',len(files),'plus HTML/JSON indexes and plans')
print('Listing characters:',{'name':5,'subtitle':len(subtitle),'promotionalText':len(promo),'keywords':len(keywords)})
