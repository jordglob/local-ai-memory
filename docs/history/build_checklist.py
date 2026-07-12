#!/usr/bin/env python3
"""Printable A4 installation checklist v3 — English, generic, headless-ready."""
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib import colors
from reportlab.platypus import (SimpleDocTemplate, Paragraph, Spacer,
                                 Table, TableStyle, PageBreak, HRFlowable, KeepTogether)

doc = SimpleDocTemplate("/mnt/user-data/outputs/installation-checklist.pdf",
                        pagesize=A4, topMargin=15*mm, bottomMargin=14*mm,
                        leftMargin=18*mm, rightMargin=18*mm,
                        title="AI Memory Stack — Installation Checklist")
ss = getSampleStyleSheet()
TITLE = ParagraphStyle('T', parent=ss['Title'], fontSize=20, spaceAfter=2)
SUB   = ParagraphStyle('S', parent=ss['Normal'], fontSize=10, textColor=colors.grey, spaceAfter=8)
H1    = ParagraphStyle('H1', parent=ss['Heading1'], fontSize=14, spaceBefore=12, spaceAfter=5,
                       textColor=colors.HexColor('#1a3a5c'))
H2    = ParagraphStyle('H2', parent=ss['Heading2'], fontSize=11.5, spaceBefore=9, spaceAfter=3)
BODY  = ParagraphStyle('B', parent=ss['Normal'], fontSize=10, leading=13.5)
SMALL = ParagraphStyle('Sm', parent=ss['Normal'], fontSize=8.5, leading=11, textColor=colors.grey)
STEP  = ParagraphStyle('St', parent=ss['Normal'], fontSize=10, leading=14.5, leftIndent=6)
WARN  = ParagraphStyle('W', parent=ss['Normal'], fontSize=9.5, leading=13,
                       backColor=colors.HexColor('#fff6e0'), borderPadding=6,
                       borderColor=colors.HexColor('#e0b040'), borderWidth=0.7)
CB = '\u2610'; LINE = '_' * 36

def step(t): return Paragraph(f'{CB}&nbsp;&nbsp;{t}', STEP)
def fill(label, w=62):
    t = Table([[Paragraph(label, BODY),
                Paragraph('<font color="#999999">' + LINE + '</font>', BODY)]],
              colWidths=[w*mm, None])
    t.setStyle(TableStyle([('VALIGN',(0,0),(-1,-1),'BOTTOM'),
                           ('BOTTOMPADDING',(0,0),(-1,-1),4),
                           ('LEFTPADDING',(0,0),(0,0),0)]))
    return t

S = []
S.append(Paragraph("AI Memory Stack", TITLE))
S.append(Paragraph("Installation Checklist — from blank machine to a running local AI · v3.0", SUB))
S.append(HRFlowable(width="100%", color=colors.HexColor('#1a3a5c'), thickness=1.2))
S.append(Spacer(1, 5))
S.append(Paragraph(
    "<b>How to use this:</b> print it, keep it next to the machine, tick every box in order. "
    "Fill in the blanks as you go — usernames, hostnames, wifi — so everything is in one place. "
    "Never skip ahead: each block builds on the previous one.", BODY))
S.append(Spacer(1, 3))
S.append(Paragraph(
    "<b>Passwords:</b> a password manager (Bitwarden, 1Password, KeePassXC) is the first choice. "
    "The lines below say \"password <i>or</i> hint — your choice\". Be aware: filled in, this sheet "
    "is a complete access kit to the machine (passwords + IP + username on one page). "
    "Lock it away. Shred it on disposal. Never photograph it.", WARN))

S.append(Paragraph("Step 0 — Pick a machine (5 min)", H1))
S.append(Paragraph(
    "Windows is supported via WSL2 only (the script prints exact instructions if you run it there). "
    "For a clean local-first install, macOS or Linux Mint is simpler.", BODY))
S.append(Spacer(1, 3))
t = Table([
 [Paragraph('<b>RAM</b>', BODY), Paragraph('<b>What you can run</b>', BODY)],
 [Paragraph('8 GB (minimum)', BODY), Paragraph('3B models — works, but limited quality', BODY)],
 [Paragraph('16 GB', BODY), Paragraph('7–14B models — good daily assistant', BODY)],
 [Paragraph('32–48 GB (recommended)', BODY), Paragraph('32–35B models — strong local agent', BODY)],
], colWidths=[55*mm, None])
t.setStyle(TableStyle([('BACKGROUND',(0,0),(-1,0),colors.HexColor('#eef2f7')),
 ('GRID',(0,0),(-1,-1),0.5,colors.HexColor('#c0c8d4')),
 ('TOPPADDING',(0,0),(-1,-1),3),('BOTTOMPADDING',(0,0),(-1,-1),3)]))
S.append(t)
S.append(Spacer(1, 4))
S.append(Paragraph("Also needed: 60+ GB free disk (20 GB absolute minimum), internet for the install.", BODY))
S.append(step("I am installing on: &nbsp;\u2610 Mac &nbsp;&nbsp;\u2610 PC with Linux Mint"))
S.append(fill("Machine name / location:"))
S.append(Paragraph("<i>Tip: start with ONE machine. The second install takes 15 minutes with this same list.</i>", SMALL))

S.append(PageBreak())
S.append(Paragraph("Track A — Mac: clean reinstall (45–60 min)", H1))
S.append(Paragraph("Skip to Track B if you chose Linux Mint.", SMALL))
S.append(Paragraph("A1. Enter Recovery Mode — depends on your Mac's chip", H2))
S.append(step("Back up anything you want to keep (external drive or another machine)"))
S.append(step("Find your chip type:  → About This Mac. Tick one: &nbsp;\u2610 Apple Silicon (M1–M4) &nbsp;&nbsp;\u2610 Intel"))
S.append(step("<b>Apple Silicon:</b> shut down fully → press and HOLD the power button until 'Loading startup options' → Options → Continue"))
S.append(step("<b>Intel:</b> shut down → press power, then immediately hold <b>Cmd+R</b> until the Apple logo appears"))
S.append(Paragraph("A2. Erase and reinstall macOS", H2))
S.append(step("Disk Utility → select 'Macintosh HD' → Erase (format: APFS) → quit Disk Utility"))
S.append(step("Reinstall macOS → follow the wizard (20–40 min, several restarts)"))
S.append(Paragraph("A3. First-run setup — WITHOUT cloud", H2))
S.append(step("Language / country / keyboard → connect to wifi"))
S.append(fill("Wifi network:", 38))
S.append(step("At 'Sign in with your Apple ID': choose <b>Set Up Later</b> / <b>Skip</b> — macOS requires NO account"))
S.append(step("Create the local computer account:"))
S.append(fill("&nbsp;&nbsp;&nbsp;&nbsp;Full name:", 38))
S.append(fill("&nbsp;&nbsp;&nbsp;&nbsp;Account name (short, lowercase):", 60))
S.append(fill("&nbsp;&nbsp;&nbsp;&nbsp;Password or hint (your choice — see warning, p.1):", 86))
S.append(step("Decline: Siri analytics, usage data sharing, Screen Time (all can be enabled later)"))
S.append(step("FileVault (disk encryption): recommended if theft is a risk. If enabled, store the recovery key in your password manager"))
S.append(step("On the desktop: run Software Update ( → System Settings → General → Software Update)"))
S.append(step("<b>Power settings (do this NOW — sleep kills downloads and remote access):</b> System Settings → search 'sleep' → prevent sleeping when display is off / set sleep to Never. Screen turning off is fine — system sleep is not"))
S.append(step("Open <b>Terminal</b> (Cmd+Space, type 'terminal', Enter) → go to <b>Step 2</b> on page 4"))
S.append(Spacer(1, 3))
S.append(Paragraph(
    "On Mac the script will pause and tell you exactly which security popup to expect "
    "(Xcode tools ~5–8 min, 'ollama was blocked', firewall). That is normal — it waits for you. "
    "One password prompt is normal on macOS: the Homebrew installer asks for your account "
    "password in the terminal (not a popup) the first time. Your first macOS account is an "
    "admin account — keep it that way on this machine; the tools require it. "
    "You may also see a notification 'Background items added' (Ollama) — that is expected.", WARN))

S.append(PageBreak())
S.append(Paragraph("Track B — Linux Mint on a PC (60–90 min)", H1))
S.append(Paragraph("B1. Create the USB installer (on any working computer)", H2))
S.append(step("Download Linux Mint 22 'Cinnamon' ISO from <b>linuxmint.com/download.php</b>"))
S.append(step("Download <b>balenaEtcher</b> (etcher.balena.io)"))
S.append(step("Insert a USB stick (8 GB+ — <b>everything on it is erased</b>)"))
S.append(step("Etcher: pick the ISO → pick the stick → Flash (5–10 min)"))
S.append(Paragraph("B2. Boot the PC from the stick", H2))
S.append(step("Insert stick, power on, immediately tap the boot-menu key repeatedly:"))
S.append(Paragraph("&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Common: <b>F12</b> (Dell/Lenovo) · <b>F9</b> (HP) · <b>F8/F11</b> (Asus/MSI) · <b>Esc</b> (older)", BODY))
S.append(fill("My PC's boot key turned out to be:", 60))
S.append(step("Pick the USB stick → 'Start Linux Mint'"))
S.append(step("If it refuses: enter BIOS (<b>Del</b> or <b>F2</b>) → disable 'Secure Boot' → retry"))
S.append(Paragraph("B3. Install", H2))
S.append(step("Double-click <b>Install Linux Mint</b> on the desktop"))
S.append(step("Language / keyboard → tick 'Install multimedia codecs'"))
S.append(step("Installation type: <b>Erase disk and install Mint</b> (if the PC is dedicated)"))
S.append(step("Encryption (LVM + encrypt): recommended if theft is a risk — store the passphrase in your password manager (asked at EVERY boot)"))
S.append(step("Create the user:"))
S.append(fill("&nbsp;&nbsp;&nbsp;&nbsp;Your name:", 35))
S.append(fill("&nbsp;&nbsp;&nbsp;&nbsp;Computer name (hostname):", 52))
S.append(fill("&nbsp;&nbsp;&nbsp;&nbsp;Username (lowercase):", 48))
S.append(fill("&nbsp;&nbsp;&nbsp;&nbsp;Password or hint (your choice — see warning, p.1):", 86))
S.append(step("Install (15–25 min) → restart → remove the stick when asked"))
S.append(Paragraph("B4. After first login", H2))
S.append(step("Update Manager (shield icon) → install ALL updates → restart"))
S.append(step("<b>Power settings (NOW):</b> Menu → Power Management → set 'suspend when inactive' to Never. Screen blanking is fine — system suspend is not"))
S.append(step("<b>Old PC?</b> If the BIOS clock was wrong or settings were forgotten: replace the CMOS battery (CR2032, ~2 €) — a dead one also forgets the power setting below"))
S.append(step("<b>BIOS 'Restore on AC Power Loss':</b> reboot → enter BIOS (Del/F2) → Power settings → set to <b>Power On</b> (makes the PC boot by itself after an outage)"))
S.append(step("Open <b>Terminal</b> (Ctrl+Alt+T) → go to <b>Step 2</b>"))
S.append(Spacer(1, 3))
S.append(Paragraph(
    "On Linux the script asks for your login password ONCE at the start ('sudo') to install "
    "system packages. That is the only time. Never start the script itself with sudo.", WARN))

S.append(PageBreak())
S.append(Paragraph("Step 2 — The AI layer (same for Mac and Linux)", H1))
S.append(Paragraph(
    "Three scripts, run in order. They handle the classic beginner traps (PATH, sudo, "
    "dependencies, interruptions) — your job is: run, read, tick.", BODY))
S.append(Paragraph("2.1 Get the scripts and start — exactly like this", H2))
S.append(step("In the machine's web browser, open the project page (github.com/YOUR-USERNAME/local-ai-memory) → green <b>Code</b> button → <b>Download ZIP</b>. It lands in <b>Downloads</b>"))
S.append(step("Double-click the ZIP in Downloads so a folder appears (macOS does this automatically)"))
S.append(step("In the terminal, go to that folder:&nbsp;&nbsp;<b>cd ~/Downloads/local-ai-memory-main</b>&nbsp;&nbsp;<i>(cd = change directory; press Tab to auto-complete the name)</i>"))
S.append(step("Sanity check — type:&nbsp;&nbsp;<b>ls ai-memory-*.sh</b>&nbsp;&nbsp;You should see the script files listed. If 'No such file or directory': you are in the wrong folder — run the cd line again"))
S.append(Paragraph("<i>The installer copies all scripts to a permanent home (~/Documents/ai-memory/.tools/) — after step 2.2 you can delete the download and every later command uses that path.</i>", SMALL))
S.append(Paragraph("2.2 Install (15–25 min; Intel Mac 25–35; slow internet adds 10–20)", H2))
S.append(step("In the terminal:&nbsp;&nbsp;<b>bash ai-memory-setup.sh</b>"))
S.append(step("Linux: type your password ONCE when asked (sudo)"))
S.append(step("Mac: approve the popups when the script pauses and points at them — including the folder-access prompts ('Terminal would like to access Documents/Downloads'): click <b>OK/Allow</b>"))
S.append(step("Mac + iCloud Desktop&amp;Documents sync: the script detects it and offers ~/ai-memory instead, so your vault stays OFF the cloud — accept"))
S.append(step("Answer the two questions: install Hermes Agent? · start Ollama at login? (Enter = yes)"))
S.append(step("Wait for the green box: <b>'Installation complete — no errors'</b>"))
S.append(step("If RED: read the last line, fix, run the same command again — it resumes where it stopped"))
S.append(fill("Done — date/time:", 42))
S.append(Paragraph("2.3 Configure (5–10 min + optional model download)", H2))
S.append(step("Open a NEW terminal window (Cmd+N / Ctrl+Shift+N)"))
S.append(step("Run:&nbsp;&nbsp;<b>bash ~/Documents/ai-memory/.tools/ai-memory-configure.sh</b>"))
S.append(step("It analyzes your hardware and suggests the best model — Enter to accept"))
S.append(step("If it offers a download: <b>y</b> (a 35B model is ~20 GB; 30+ min on slow lines)"))
S.append(step("API keys: just press <b>Enter</b> twice to skip — everything runs locally anyway"))
S.append(fill("Selected model:", 38))
S.append(Paragraph("2.4 Import your history (5–15 min)", H2))
S.append(step("Order your exports first (each takes minutes to arrive by email):"))
S.append(Paragraph("&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Claude: claude.ai → Settings → Privacy → Export Data &nbsp;·&nbsp; ChatGPT: Settings → Data Controls → Export", BODY))
S.append(step("Put the downloaded ZIP(s) in this machine's Downloads folder"))
S.append(step("Run:&nbsp;&nbsp;<b>bash ~/Documents/ai-memory/.tools/ai-memory-ingest.sh</b> — it finds exports and local tool histories itself and asks before importing"))
S.append(step("10 sources supported — see them all with <b>--list-sources</b>"))
S.append(fill("Conversations imported:", 50))
S.append(Paragraph("2.5 First run — the test", H2))
S.append(step("Run:&nbsp;&nbsp;<b>hermes chat</b>&nbsp;&nbsp;(or: bash ~/Documents/ai-memory/.tools/resume.sh)"))
S.append(step("Ask about something from your imported history — verify it can find it"))
S.append(step("DONE. File this checklist (locked away) or shred it"))
S.append(Spacer(1, 6))
S.append(KeepTogether([
    Paragraph("Machine identity (the install script prints these values — just copy)", H2),
    fill("Hostname:", 30), fill("Local IP:", 30),
    fill("SSH line (ssh user@ip):", 50),
    fill("WireGuard endpoint (domain or IP:51820):", 70),
    fill("Tailscale IP/name (if used):", 56),
    fill("RustDesk ID (if used):", 46)]))

S.append(PageBreak())
S.append(Paragraph("Headless node (optional) — reach this machine without a screen", H1))
S.append(Paragraph(
    "Run this AFTER Step 2, while you still have a screen and keyboard connected. "
    "It is the last time you need them.", BODY))
S.append(step("Run on your <b>MAIN computer first</b>:&nbsp;&nbsp;<b>bash ~/Documents/ai-memory/.tools/ai-memory-remote.sh</b> → answer <b>1) MAIN</b>. It creates your SSH key (one per client machine, never copied) and shows the public key — add it to GitHub (Settings → SSH keys)"))
S.append(fill("Main machine — key fingerprint (printed by the script):", 92))
S.append(step("Then run the same script <b>on each node</b> → answer <b>2) NODE</b>"))
S.append(step("Part 1–2: enables SSH and installs your public key (easiest: the GitHub username option)"))
S.append(step("Part 3: verify key login FROM YOUR OTHER COMPUTER before letting it disable password login"))
S.append(step("Part 4 — remote networking: the script analyzes your connection and recommends a path. <b>WireGuard (fully local) is the first choice</b>; Tailscale is offered for convenience or behind carrier-NAT (CGNAT)"))
S.append(step("If WireGuard: forward <b>UDP 51820</b> to the hub machine in your router. Note the endpoint on the identity block"))
S.append(step("<b>Verify from OUTSIDE only</b> — turn off phone wifi, connect over mobile data, test the tunnel. Do NOT trust 'port checker' sites: WireGuard is silent by design and they wrongly say 'closed'"))
S.append(step("Part 5 (optional): RustDesk for the graphical moments (macOS popups)"))
S.append(step("Part 6: always-on power profile (no sleep, auto-restart after power loss)"))
S.append(step("Mac only: HDMI <b>dummy plug</b> (~10 €) in a video port — without it remote graphics is slow and blurry"))
S.append(step("Mac only: enable autologin (System Settings → Users &amp; Groups) so services return after a reboot — requires FileVault OFF (tradeoff on the Tips page)"))
S.append(step("<b>MANDATORY pull-the-plug test:</b> shut down → pull the cord → wait 1 min → plug in. The machine must boot and answer SSH by itself. PCs: fix in BIOS if not. Apple Silicon minis: known to sometimes ignore the setting — if so, plan for a physical button press after outages"))
S.append(step("Always keep TWO ways in (SSH + one graphical) — an update can break either one"))

S.append(PageBreak())
S.append(Paragraph("Tips & Tricks (after everything works)", H1))
S.append(Paragraph("cmux — run several AI agents side by side (macOS)", H2))
S.append(Paragraph(
    "A native, open-source terminal built on Ghostty's renderer, designed for agent work: a vertical "
    "sidebar shows each workspace's git branch and latest notification, and a panel lights up when an "
    "agent needs your input. Free, no telemetry, no account. Install AFTER the base setup works: "
    "download from <b>cmux.io</b> or GitHub (sst/cmux). Linux alternative: Ghostty (same engine, "
    "without the agent features) or plain tmux.", BODY))
S.append(Paragraph("Tools that strengthen the AI workflow (optional, open-source)", H2))
S.append(Paragraph(
    "All install after the base setup; each is one command. "
    "<b>cmux</b> (macOS) — run several agents side by side. "
    "<b>llama.cpp</b> — the engine under many runtimes; GGUF conversion and benchmarking. "
    "<b>litellm</b> — a local proxy giving one OpenAI-style endpoint across Ollama and cloud fallbacks. "
    "<b>whisper.cpp</b> — local speech-to-text, so voice notes never leave the machine. "
    "<b>ripgrep</b> (rg) — instant full-text search across the vault. "
    "<b>jq</b> — inspect the JSON the importers read. "
    "A commercial VPN (Mullvad etc.) can be installed too, but it competes with your own "
    "WireGuard tunnel for routing — use one at a time.", BODY))
S.append(Paragraph("Syncthing — sync the vault between machines, no cloud", H2))
S.append(Paragraph(
    "Free, peer-to-peer, encrypted. Install on both machines (<b>syncthing.net</b>), share the vault "
    "folder (~/Documents/ai-memory). Your conversations never touch a third-party server. "
    "Do NOT sync ~/.hermes between machines — agent state is per-machine.", BODY))
S.append(Paragraph("Backups — two things matter", H2))
S.append(Paragraph(
    "1) The vault (~/Documents/ai-memory) — plain files, any backup tool works; even a periodic "
    "copy to a USB drive is fine. 2) ~/.hermes — the agent's memory and config. Time Machine (Mac) "
    "or Timeshift+home backup (Mint) covers both. Test a restore once.", BODY))
S.append(Paragraph("Update Advisor — built in", H2))
S.append(Paragraph(
    "The agent's workspace instructions include a read-only update check: ask it to 'check for "
    "updates' and it writes a report with exact upgrade commands to 00-Inbox/UPDATES.md. "
    "It never upgrades anything by itself — you decide.", BODY))
S.append(Paragraph("Disk encryption (FileVault / LUKS) — an honest tradeoff", H2))
S.append(Paragraph(
    "On a laptop that leaves the house: enable it (theft protection). On a headless always-on "
    "node: it blocks unattended reboots — the machine stops at a pre-boot password screen no "
    "remote tool can reach. Pick based on where the machine lives. If your router ever hands "
    "out new IPs, set a DHCP reservation for each node so the identity block stays true. "
    "Prefer zero cloud? Plain WireGuard replaces Tailscale at the cost of manual key setup.", BODY))
S.append(Paragraph("macOS folder popups (power-user shortcut)", H2))
S.append(Paragraph(
    "Each first access to Documents/Downloads triggers an Allow prompt. Granting Terminal "
    "<b>Full Disk Access</b> once (System Settings → Privacy &amp; Security) removes them all — "
    "convenient, but it means anything run in that terminal can read everything. "
    "Per-folder approval is the safer default; FDA is for those who know the tradeoff.", BODY))
S.append(Paragraph("If something gets stuck", H2))
S.append(Paragraph(
    "1) Read the last red line — the scripts always say WHAT failed and what to do. "
    "2) Re-run the same command — everything resumes where it stopped. "
    "3) The log lives at ~/Documents/ai-memory/.tools/setup.log — show it to an AI assistant and "
    "troubleshoot together. 4) Nothing in these steps can break the computer — worst case is "
    "restarting from Step 2.", BODY))

doc.build(S)
print("PDF v3 built")
