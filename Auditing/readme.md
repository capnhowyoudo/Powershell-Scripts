# ⚠️ Use At Your Own Risk — PowerShell Scripts

**Supported:** PowerShell 5.1 / PowerShell 7+

---

## Disclaimer

This PowerShell script is provided **as-is, without warranty of any kind.** By running or using these scripts, you accept full responsibility for any consequences — including data loss, system instability, security issues, or legal and regulatory impacts.

> Do not run these scripts on production systems unless you understand every line and have tested them in a safe environment.

---

## Recommended Precautions

1. **Test in a sandbox or VM first** — use a disposable virtual machine or container before running anywhere that matters.
2. **Back up your data** — always back up files, system settings, the registry, or user accounts before running scripts that modify them.
3. **Review every line** — read the entire script before executing it. Never run blindly.
4. **Run with least privilege** — only elevate to Administrator when absolutely necessary.
5. **Use `-WhatIf` / `-Confirm`** — take advantage of these switches on supported cmdlets while testing.
6. **Check execution policies** — run `Get-ExecutionPolicy -List` to understand your system's current policies; avoid changing global policies permanently.
7. **Prefer signed scripts** — for any production use, consider signing scripts with an Authenticode certificate.
8. **Use source control** — track changes in Git and require code review before deploying updates.

---

## Requirements

- PowerShell 7+ or Windows PowerShell 5.1
- Administrator privileges (only if required by the specific script's actions)
