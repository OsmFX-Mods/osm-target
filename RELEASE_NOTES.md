## What's Changed

- **Global options without a target** (opt-in, `Config.Interaction.globalsWithoutTarget` or the new toggle in `/targetadmin` > Options): like ox_target, `addGlobalOption` options can now appear when you are not aiming at anything, in a menu just in front of the player. Turn it on for escort/drag scripts such as p_policejob, whose "Release" option otherwise only showed on nearby poles and cones.
- **Per-option control** with `showWithoutTarget = true / false` on any global option.
- Off by default: existing servers behave exactly as before until it is enabled.
