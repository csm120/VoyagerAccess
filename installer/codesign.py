"""Authenticode-sign Windows files with Azure Artifact Signing.

    py -3.11 installer\\codesign.py <file> [<file> ...]
    py -3.11 installer\\codesign.py --check <file> ...
    codesign.py --can-sign                  (exit 0 if this machine can sign)
    codesign.py --inno-sign-tool <json>     (prints the ISCC /Swfh= command)

THIS IS NOT AN UPDATER'S OWN CHECK. An app's updater may verify its downloads
its own way (ACE's `lib/signing.py` is an Ed25519 signature, for one).
Authenticode is Windows' check: it puts "Web Friendly Help LLC" in the
publisher line of a download and an installer and is what SmartScreen builds
reputation on. Neither substitutes for the other.

HOW IT SIGNS. signtool, with Microsoft's Artifact Signing helper DLL loaded
through /dlib. The private key never leaves Microsoft's hardware; the helper
asks for a signature using whoever is signed in to the Azure CLI, which on
Casey's machine is help@webfriendlyhelp.com, holding the "Artifact Signing
Certificate Profile Signer" role. The account, profile and endpoint below are
not secrets: without that login they let nobody sign anything.

THE CERTIFICATES LAST THREE DAYS, so every signature is timestamped. Without
the timestamp a signed release would turn invalid that weekend.

NOTHING HERE IS ACE-SPECIFIC on purpose, so the same file serves Casey's other
Windows apps. Set-up and history: C:\\OneDrive\\Downloads\\WFH\\review\\
operations\\code-signing-setup.md.
"""

from __future__ import annotations

import glob
import json
import os
import shutil
import subprocess
import sys
import tempfile

ENDPOINT = "https://eus.codesigning.azure.net/"
ACCOUNT = "wfhsigning"
PROFILE = "wfh-public"
TIMESTAMP_URL = "http://timestamp.acs.microsoft.com"

# What a correct signature names. Checked after signing rather than trusting
# signtool's exit code, so a file signed by some other certificate on this
# machine (a test one, say) cannot pass for a release signature.
PUBLISHER = "CN=Web Friendly Help LLC"

# Overrides, for a machine where the tools live somewhere unusual.
SIGNTOOL_ENV = "WFH_SIGNTOOL"
DLIB_ENV = "WFH_SIGNING_DLIB"

AZ_DEFAULT_DIR = r"C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin"

# Every credential the helper would otherwise try before the Azure CLI. Left
# in, the browser one can pop a sign-in window in the middle of a build, and
# the shared-cache one can sign in as csm120 instead of help@.
EXCLUDED_CREDENTIALS = [
    "ManagedIdentityCredential", "EnvironmentCredential",
    "WorkloadIdentityCredential", "SharedTokenCacheCredential",
    "VisualStudioCredential", "VisualStudioCodeCredential",
    "AzurePowerShellCredential", "AzureDeveloperCliCredential",
    "InteractiveBrowserCredential",
]


def _version_key(path: str) -> tuple:
    """Sort key from the numeric folder names in a path, so 10.0.26100.0 beats
    10.0.9200.0, which a plain string sort gets backwards."""
    parts = []
    for piece in path.replace("\\", "/").split("/"):
        if piece.replace(".", "").isdigit():
            parts.append(tuple(int(n) for n in piece.split(".")))
    return tuple(parts)


def find_signtool() -> str | None:
    override = os.environ.get(SIGNTOOL_ENV)
    if override:
        return override if os.path.isfile(override) else None
    kits = os.path.join(
        os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)"),
        "Windows Kits", "10", "bin", "*", "x64", "signtool.exe",
    )
    found = sorted(glob.glob(kits), key=_version_key)
    return found[-1] if found else None


def find_dlib() -> str | None:
    override = os.environ.get(DLIB_ENV)
    if override:
        return override if os.path.isfile(override) else None
    pattern = os.path.join(
        os.environ.get("LOCALAPPDATA", ""), "ArtifactSigning", "*", "bin", "x64",
        "Azure.CodeSigning.Dlib.dll",
    )
    found = sorted(glob.glob(pattern), key=_version_key)
    return found[-1] if found else None


def find_az_dir() -> str | None:
    az = shutil.which("az")
    if az:
        return os.path.dirname(az)
    if os.path.isfile(os.path.join(AZ_DEFAULT_DIR, "az.cmd")):
        return AZ_DEFAULT_DIR
    return None


def missing() -> list[str]:
    """What this machine lacks for signing, in words. Empty means it can sign."""
    if sys.platform != "win32":
        return ["this is not Windows"]
    gaps = []
    if not find_signtool():
        gaps.append("signtool (Windows SDK)")
    if not find_dlib():
        gaps.append(
            "the Artifact Signing helper (NuGet Microsoft.ArtifactSigning.Client, "
            r"unpacked into %LOCALAPPDATA%\ArtifactSigning\<version>)"
        )
    if not find_az_dir():
        gaps.append("the Azure CLI, signed in as help@webfriendlyhelp.com")
    return gaps


def environment() -> dict:
    """The environment to run signtool in: the Azure CLI must be on PATH, or the
    helper cannot find the login and fails with an authentication error that
    says nothing about PATH."""
    env = dict(os.environ)
    az_dir = find_az_dir()
    if az_dir:
        env["PATH"] = az_dir + os.pathsep + env.get("PATH", "")
    return env


def write_metadata(folder: str) -> str:
    path = os.path.join(folder, "artifact-signing.json")
    with open(path, "w", encoding="utf-8") as handle:
        json.dump({
            "Endpoint": ENDPOINT,
            "CodeSigningAccountName": ACCOUNT,
            "CertificateProfileName": PROFILE,
            "ExcludeCredentials": EXCLUDED_CREDENTIALS,
        }, handle, indent=2)
    return path


def sign_arguments(metadata: str) -> list[str]:
    """Everything after `signtool sign` except the files."""
    return [
        "/fd", "SHA256",
        "/tr", TIMESTAMP_URL, "/td", "SHA256",
        "/dlib", find_dlib() or "",
        "/dmdf", metadata,
    ]


def inno_sign_tool(metadata: str) -> str:
    """The command Inno Setup runs to sign the installer and its uninstaller,
    for ISCC's /S switch. Inno replaces $q with a quote and $f with the quoted
    file name; real quotes would be mangled on their way through
    subprocess, so every quote is written as $q."""
    parts = [find_signtool() or "", "sign", *sign_arguments(metadata)]
    return " ".join(f"$q{part}$q" for part in parts) + " $f"


def signer(path: str) -> str | None:
    """The subject of a VALID Authenticode signature on `path`, or None.

    Asked of Windows itself through Get-AuthenticodeSignature, which checks the
    chain and the hash, so a file changed after signing reads as invalid here.
    The path goes in through the environment rather than the command line, so
    no quoting can turn a file name into PowerShell.

    PSModulePath IS DROPPED, and that is not tidiness. Run from PowerShell 7,
    the inherited value points Windows PowerShell at PowerShell 7's modules, it
    fails to load Microsoft.PowerShell.Security, prints the error on stderr and
    nothing on stdout, and EVERY file reads as unsigned, including a validly
    signed one. Measured 2026-10-12; the Microsoft-signed test caught it."""
    script = (
        "$s = Get-AuthenticodeSignature -LiteralPath $env:WFH_SIGN_CHECK; "
        "if ($s.Status -eq 'Valid') { $s.SignerCertificate.Subject }"
    )
    env = {k: v for k, v in os.environ.items() if k.upper() != "PSMODULEPATH"}
    env["WFH_SIGN_CHECK"] = os.path.abspath(path)
    result = subprocess.run(
        ["powershell", "-NoProfile", "-NonInteractive", "-Command", script],
        capture_output=True, text=True, env=env,
    )
    subject = result.stdout.strip()
    return subject or None


def is_ours(path: str) -> bool:
    subject = signer(path)
    return bool(subject) and subject.startswith(PUBLISHER + ",")


def sign(paths: list[str]) -> None:
    """Sign every file in ONE signtool call, then prove each one is signed by
    Web Friendly Help LLC. Raises SystemExit on any failure."""
    gaps = missing()
    if gaps:
        raise SystemExit("cannot sign; this machine lacks: " + "; ".join(gaps))
    with tempfile.TemporaryDirectory() as folder:
        metadata = write_metadata(folder)
        result = subprocess.run(
            [find_signtool(), "sign", *sign_arguments(metadata), *paths],
            env=environment(), capture_output=True, text=True,
        )
    if result.returncode != 0:
        raise SystemExit(
            "signtool failed:\n" + (result.stdout + result.stderr).strip()[-2000:]
        )
    unsigned = [p for p in paths if not is_ours(p)]
    if unsigned:
        raise SystemExit(
            "signtool reported success but these are not validly signed by "
            + PUBLISHER + ": " + ", ".join(unsigned)
        )
    for path in paths:
        print(f"  signed {os.path.basename(path)}")


def main(argv: list[str]) -> int:
    # For build scripts that are not Python. --can-sign exits 0 when this
    # machine can sign and otherwise prints what it lacks. --inno-sign-tool
    # writes the metadata file at the path given and prints the command for
    # ISCC's /Swfh= switch; the caller must put the Azure CLI on PATH for ISCC.
    if argv[:1] == ["--can-sign"]:
        gaps = missing()
        print("can sign" if not gaps else "cannot sign; lacks: " + "; ".join(gaps))
        return 1 if gaps else 0
    if argv[:1] == ["--inno-sign-tool"] and len(argv) == 2:
        metadata = os.path.abspath(argv[1])
        os.makedirs(os.path.dirname(metadata), exist_ok=True)
        os.replace(write_metadata(os.path.dirname(metadata)), metadata)
        print(inno_sign_tool(metadata))
        return 0
    check = "--check" in argv
    files = [a for a in argv if a != "--check"]
    if not files:
        print(__doc__)
        return 2
    if check:
        bad = 0
        for path in files:
            subject = signer(path)
            print(f"{path}: {subject or 'NOT VALIDLY SIGNED'}")
            bad += not (subject and subject.startswith(PUBLISHER + ","))
        return 1 if bad else 0
    sign(files)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
