# Complete Manual Testing Guide: Multi-Method Election Delivery System
> Comprehensive test procedure covering all 4 phases specified in `Election-Methods.pdf`.

---

## 📌 Overview of Test Phases

| Phase | Delivery Area | Key Features Tested |
|---|---|---|
| **Phase 1** | Foundation & Wizard Configuration | Method 1 vs Method 2 toggle, Mobile/Web/Hybrid selectors, Venue parameters, delivery chips & hero badges. |
| **Phase 2** | Method 1: Web Direct Link & Telemetry | Web OTP request & verify, 24-hr single-use cryptographic tokens, standalone direct voting, atomic token burn (`410 Gone`), and turnout channel telemetry bar. |
| **Phase 3** | Method 2: Venue Voting Kiosks | Station PIN authorization (`1234`), Voter ID / QR check-in, 2nd-layer OTP security, fullscreen secret ballot, and animated 5-second auto-reset loop. |
| **Phase 4** | Directory Badges & Audit Exports | Voter roll channel chips (`📱 App`, `🌐 Web`, `🏛️ Venue`, `⏳ Pending`), channel filter chips, CSV export with verification columns, and Auditor JSON export. |

---

## 🔑 Prerequisites & Environment Setup

- **Frontend App**: `http://localhost:3000`
- **Backend API**: `http://localhost:8000`
- **Default Station Security PIN**: `1234`
- **Administrator Login**:
  - **Email**: `admin@example.com` (or existing organization administrator email)
  - **Password**: `Admin@12345`

---

## 🧪 Phase 1: Foundation, Method Selection Wizard & Badges

### Objective
Verify that elections can be created with distinct delivery rules (Method 1: Mobile / Web / Hybrid vs Method 2: Physical Venue) and that public/admin cards accurately reflect these methods.

### Detailed Test Steps
1. Log in to the application as an **Organization Admin**.
2. From the navigation bar or dashboard, click **"Create Election"** (नयाँ निर्वाचन सिर्जना).
3. **Step 1 (General Information)**:
   - Enter Title: `Nepal Medical Association Central Council Election 2083`
   - Select Dates, Categories, and Guidelines. Click **Next Step**.
4. **Step 2 (Voting Method & Rules)**:
   - **Test Option A: Method 1 (Online / Remote Voting)**:
     - Select **"Online / Remote Voting"**.
     - Test the 3 delivery subtypes:
       - 📱 **Mobile App Only**: Biometrically authenticated app-only sessions.
       - 🌐 **Web-Based**: OTP-delivered magic ballot links.
       - 🔄 **Hybrid Delivery**: Allows both mobile app and web magic links.
   - **Test Option B: Method 2 (Physical Venue / Device-Based In-Person Kiosks)**:
     - Select **"Physical Venue / Device-Based"**.
     - Verify that Venue-specific inputs appear:
       - **Venue Name**: e.g., `NMA Hall, Exhibition Road, Kathmandu`
       - **Venue Address**: e.g., `Bhrikutimandap, Kathmandu`
       - **2nd-Layer Verification**: Toggle `"Require SMS/Email OTP at physical booth"` ON or OFF.
5. Finish the remaining wizard steps (Positions, Candidates, Rules) and click **Publish / Save**.
6. **Verify Display Badges**:
   - Navigate to the **Elections Directory** (`/#/elections`).
   - Observe the election card: Verify the delivery chip (e.g. `🌐 Web-Based`, `📱 Mobile App`, `🔄 Hybrid`, or `🏛️ Venue: NMA Hall`).
   - Click the election to open **Election Details**: Verify the dedicated **"Voting Method & Delivery Specification"** banner in the hero card.

---

## 🧪 Phase 2: Method 1 (Online/Remote Web Direct Link Flow & Telemetry)

### Objective
Verify the end-to-end flow for remote voters requesting a magic ballot link via OTP, casting a vote without requiring account login, verifying atomic token destruction (`410 Gone`), and checking admin turnout telemetry.

### Detailed Test Steps
1. **Request a Magic Ballot Link**:
   - Open a **Web-Based** or **Hybrid** election currently in state `Voting Open` (मतदान सुरु).
   - Click **"Get Web Ballot Link (मतदान लिङ्क पाउनुहोस्)"**.
   - Enter an enrolled voter's email or phone number.
   - Click **"Send Magic Ballot Link"**.
   - Check the Django backend console output to view the generated link:
     ```
     http://localhost:3000/#/vote/direct/<24-character-cryptographic-token>
     ```
2. **Access Direct Standalone Ballot**:
   - Copy and open the link in an **Incognito / Private Window** (no prior login required).
   - Verify that the header displays:
     - Election Title
     - Voter Legal Name and Voter ID
     - Anonymity protection assurance banner
   - Select desired candidates for each position (or choose Abstain/Boycott if permitted).
   - Click **"Cast Official Secret Ballot"**.
3. **Receipt & Cryptographic Verification**:
   - Verify that a green confirmation screen is shown.
   - Verify that a unique **SHA-256 Cryptographic Receipt Hash** is displayed.
4. **Security Verification: Single-Use Atomic Token Burn (`410 Gone`)**:
   - Refresh the page or paste the exact same ballot link again in the browser address bar.
   - **Expected Security Result**: Access is permanently denied with the error screen:
     `410 Gone — Ballot Already Submitted / मतदान गरिसकिएको छ`.
5. **Admin Turnout Telemetry Breakdown**:
   - Return to the Admin session.
   - Navigate to **Election Details** $\rightarrow$ **Voter Turnout (मतदाता सहभागिता)**.
   - In the **"Channel Verification Breakdown"** card, verify that the segmented bar reflects the newly verified `🌐 Web Link` voter.

---

## 🧪 Phase 3: Method 2 (Venue / Device-Based In-Person Voting Kiosks)

### Objective
Verify that a laptop, iPad, or tablet can be locked into an in-person Voting Kiosk booth, authenticate voters via Voter ID or QR code, cast secret ballots, and automatically reset within 5 seconds for sequential voters in line.

### Detailed Test Steps
1. **Launch Kiosk Mode**:
   - Open a **Method 2 (Venue Election)** in the Election Details screen.
   - Click the purple button: **"Launch Voting Kiosk Mode (मतदान बुथ सुरु गर्नुहोस्)"** (or navigate to `/#/elections/<electionId>/kiosk`).
2. **Station Security PIN Authorization**:
   - Enter the Election Officer Station PIN: **`1234`**.
   - Click **"Authorize Station"**.
   - **Expected Result**: Device enters dedicated, full-screen Voting Booth Mode.
3. **Voter Standby Check-In**:
   - Enter an eligible voter's registered Voter ID (e.g. `NEA-VOTE-101`) or click **"Scan QR"** to scan/paste voter credentials.
   - Click **"Unlock Ballot"**.
   - *If 2nd-Layer OTP is enabled*: Enter the 6-digit OTP code received via SMS/Email (displayed in backend logs).
   - *If Direct Unlock*: The official ballot paper opens immediately.
4. **Secret Ballot Casting & 5-Second Auto-Reset Loop**:
   - Make ballot selections on the touch-friendly interface.
   - Click **"Cast Official Secret Ballot"**.
   - **Observe the Post-Vote Confirmation**:
     - Green confirmation checkmark and cryptographic SHA-256 receipt hash.
     - **Watch the animated countdown ring**: `5... 4... 3... 2... 1... 0`.
     - **Expected Result**: At 0 seconds, the station wipes the active voter session and resets to the Standby Check-In screen ready for the next voter in line.
5. **Station Officer Exit Lock**:
   - Attempt to navigate back or click the exit icon in the top corner.
   - Enter the Officer Station PIN (`1234`) to safely release the device from Kiosk Mode.

---

## 🧪 Phase 4: Voter Roll Directory Badges & Audit Exports

### Objective
Verify that administrators can monitor live verification channels on the electoral roll, filter voters by channel, export enriched CSV data, and generate cryptographic audit packages.

### Detailed Test Steps
1. **Voter Roll Channel Badges**:
   - Navigate to **Admin** $\rightarrow$ **Voter Roll (मतदाता नामावली)** (`/#/elections/<electionId>/voters`).
   - Observe the table: Each voter displays their live channel badge:
     - `📱 App` (Indigo) — Verified via Mobile App
     - `🌐 Web` (Blue) — Verified via Web Link
     - `🏛️ Venue` (Purple) — Verified at Venue Kiosk
     - `⏳ Pending` (Grey) — Not yet verified
2. **Channel Filter Chips**:
   - Click the filter chips at the top toolbar:
     - `All`
     - `Eligible`
     - `📱 App`
     - `🌐 Web`
     - `🏛️ Venue`
     - `Ineligible`
   - Verify that the table updates instantly to match the selected channel.
3. **CSV Export Verification**:
   - Click the **"Export CSV"** button at the top right of the table.
   - Open the downloaded file `voters_export.csv` in Excel or text editor.
   - Confirm that the following columns are populated:
     - `Verification Channel`
     - `Verified At`
     - `Has Voted`
     - `Voted At`
4. **Auditor Verification Portal Export**:
   - Open **Auditor Verification Portal** from the Election Detail screen.
   - Click **"Download Audit Package (JSON)"**.
   - Inspect the downloaded JSON package:
     - Contains `election.election_method`, `election.online_type`, `election.venue_name`.
     - Contains `participation.verification_channels` count dictionary (`mobile_app`, `web_email`, `venue_kiosk`, `unverified`).
     - Contains SHA-256 `package_integrity_hash`.

---

## 📊 Summary Checklist for Testers

- [ ] **Phase 1**: Method 1 vs Method 2 created & displayed correctly.
- [ ] **Phase 2**: Magic ballot links delivered, voted anonymously, and burned with `410 Gone`.
- [ ] **Phase 3**: Kiosk mode locked with Station PIN `1234`, secret ballot cast, and 5s auto-reset loop verified.
- [ ] **Phase 4**: Voter roll badges visible, filtered by channel, CSV exported with verification columns, and audit JSON package verified.
