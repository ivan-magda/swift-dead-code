# Security

Report a vulnerability privately, through GitHub's private vulnerability reporting
(**Security → Report a vulnerability** in this repository), not in a public issue.

swift-dead-code runs `swift`, `git`, `rsync`, `xcodebuild` and `periphery` on the project you
point it at, and `scan` and `prune-imports` build that project. Treat a project you do not trust
as you would treat building it.
