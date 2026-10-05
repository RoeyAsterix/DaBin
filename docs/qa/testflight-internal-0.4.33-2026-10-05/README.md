DaBin 0.4.33 (88) internal TestFlight publication

The source, tests and QA evidence were pushed to origin/main at b7ebfb196231dc568a31e80ad36092fb98f43d50. The publication checkpoint was also committed and pushed. The release source matches the current tested fingerprint.

The first signed archive failed at codesign with errSecInternalComponent. The second reached the same signing step and was stopped by this agent to move to the interactive context recommended by Apple. Both raw logs and hashes are retained. The installed signing identity is listed as valid; that does not prove the cause of the generic signing error.

App Store Connect sign-in is renewed. Personal Testing is verified as the existing internal group, with one tester and 0.4.31 (86) in Testing. Build 88 has not been uploaded, processed or assigned.

A source-guarded interactive archive helper is prepared locally. status.json records its command, hash and receipt pattern. Computer Use refused Terminal control for safety reasons, and protected Keychain/SecurityAgent authentication requires human input. Run the prepared command on the signed-in Mac and complete its signing prompt; the authorized upload and internal assignment can then continue.

Current QA: 120 of 121 native suites passed. Zoom performance and framework table warnings remain open. The unsigned release and packaging checks passed. Signing, upload, internal readiness and Apple approval are distinct unverified stages. An active 30-minute follow-up stays quiet while the same human step is pending.
