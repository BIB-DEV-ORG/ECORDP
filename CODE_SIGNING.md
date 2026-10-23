# Code signing policy

Free code signing provided by [SignPath.io](https://about.signpath.io/), certificate by [SignPath Foundation](https://signpath.org/).

## What is signed

Only the Windows release artifacts of EcoRDP built from this repository by GitHub Actions
(`.github/workflows/flutter-build.yml`, job `build-for-windows-flutter`):

- `EcoRDP-<version>-x86_64.exe` (portable / installer)
- `EcoRDP-<version>-x86_64.msi`

Builds are never signed from a developer machine. Every signed file can be traced to a public
commit of this repository and to the GitHub Actions run that produced it.

## Team roles

| Role | Members |
|---|---|
| Committers and reviewers | Members of the [BIB-DEV-ORG](https://github.com/BIB-DEV-ORG) organization |
| Approvers | Antoine (BIB-DEV-ORG owner) |

Each signing request is approved manually by an approver in SignPath before the signed files
are published.

## Privacy policy

EcoRDP is a remote desktop client based on [RustDesk](https://github.com/rustdesk/rustdesk)
(AGPL-3.0). It only connects to other systems when the user operates it:

- the rendezvous and relay server `rdp.eco-hub.fr` operated by Eco-Hub, to reach the remote
  computer the user chooses, or to let a technician the user invited reach this computer;
- the account and address book API `https://rdp.eco-hub.fr`, only when the user signs in;
- the help service `https://rdp.eco-hub.fr/aide`, only when the program was started from a help
  session the user requested (it then announces this computer's ID and one-time password to the
  technician of that session).

Remote sessions are end-to-end encrypted between the two computers. A remote session always
shows a visible indicator and can be stopped by the local user at any time.
