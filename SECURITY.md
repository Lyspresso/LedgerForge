# Security policy

LedgerForge, Statement Studio, and Ledger Pocket are local-first applications. They do not require
an account, analytics service, API key, cloud database, or network connection. That design reduces
remote attack surface, but imported Markdown, formula evaluation, local persistence, file access,
dependencies, and application packaging still deserve security review.

## Supported versions

Security fixes target the latest published release and the current `main` branch. Older builds may
not receive backports. The release notes will identify any exception.

## Report a vulnerability privately

Do not open a public issue for a suspected vulnerability. Use GitHub's private vulnerability
reporting form:

[Report a vulnerability privately](https://github.com/Lyspresso/LedgerForge/security/advisories/new)

If GitHub says private reporting is unavailable, do not publish exploit details or sensitive test
data. Notify the repository owner through their GitHub profile and ask them to enable a private
security-advisory draft for the report.

Include, when possible:

- the affected application, version or commit, platform, and OS version;
- a concise description of the impact and required attacker capabilities;
- minimal reproduction steps using original, non-sensitive data;
- relevant logs or crash output with usernames and local paths removed; and
- any suggested remediation or temporary mitigation.

Please do not attach proprietary question banks, answer keys, student records, credentials, or a
copy of a user's Application Support data. Construct the smallest original fixture that reproduces
the issue.

The maintainer will acknowledge the report through the private advisory, assess scope, coordinate
a fix and disclosure, and credit the reporter if requested. No fixed response-time guarantee is
currently offered.

## Useful report areas

Examples include arbitrary code execution, unsafe path handling, unintended file modification or
disclosure, denial of service from a practical-size input, persistence corruption that crosses
question packs or users, formula-evaluator escapes, sandbox/signing mistakes, and exploitable
dependency vulnerabilities.

Incorrect accounting content, an unsupported Markdown construct, or an ordinary app bug without a
security or privacy impact belongs in the public bug tracker. When unsure, report privately first.
