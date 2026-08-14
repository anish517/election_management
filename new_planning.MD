# EMS — Feature & Change Requirements

Organized from raw notes into a dev checklist, grouped by module. A few items have an *assumption* noted in italics — flag if any of these don't match what you meant.

## 1. App Drawer / Settings

- [ ] Add **Payment Settings** to drawer, with a **National / International** toggle and a tab per gateway:

  **eSewa**
  - Product Code* (text)
  - Secret Key* (text)

  **Moco**
  - Merchant Id* (e.g. `M000003269`)
  - Terminal Id* (e.g. `T000000039`)
  - Outlet Id* (e.g. `O000058633`)
  - Shared Key* (text)

  **FonePay**
  - Profile Id* (text)
  - Shared Secret Key* (text)

  **Khalti**
  - Live Secret Key* (single field, e.g. `live_secret_key_...`)

  **ConnectIPS**
  - Merchant Id*
  - App Id*
  - App Name*
  - Password (Basic Auth)*
  - Requires a digital certificate (PFX file) for token signing — obtained from ConnectIPS
  - Certificate stored at a path like `storage/certificates/connectips/{id}/`
  - Callback URLs configured in the payment section
  - Environments: UAT `https://uat.connectips.com:7443`, Production `https://connectips.com:7443`
  - Network prerequisite: server IP whitelisted with ConnectIPS, port 7443 open on firewall

  **QR + Account Details** *(structured fields + file upload, not a rich-text editor)*
  - Account Name
  - Account Number
  - Bank Name
  - Branch
  - **QR Code** — image upload field, stores and displays the actual QR image

- [ ] Add **Election Rules** to drawer

review this  election_management\lib\features\admin\organization\org_settings_screen.dart
backend\apps\billing
backend\apps\organizations  .letter this will be used for real payement integration for now implement this.feature

## 2. Quota Management
- [ ] Quota field should be a **dynamic dropdown/list**, e.g. Female: 2, Dalit: 2, etc., tied to a Designation
- [ ] **Remove** quota field from the "Create Designation" form
- [ ] Create a **separate "Quota Setting"** screen instead — with **Edit** and **Delete**, tied to Designation name
- [ ] Add a **Status** field/type to Quota *(assumption: Active/Inactive toggle per quota entry)*
 that must bee see in the ballot screen. something like federal system types.
 for example same position have quota system out 5 2 have quota and 3 dont have 

## 3. Election Committee
- [ ] "Create New Election Committee": add **search-and-select-existing** (search existing members and select them instead of manual entry)
- [ ] **Remove** fields from "Create New Election Committee": Committee Name, Chair Designation, Contact Number

## 4. Voting
- [ ] **Candidates should also be able to cast a vote**
- [ ] Add a **"No Vote / Boycott" (बहिष्कार)** option per election
- [ ] Log **IP address** and **MAC address** when a voter votes. only organization can view that log 

## 5. Candidate
- [ ] **Remove** Signature field from candidate
- [ ] **Remove** Slate/Party Name field from candidate
- [ ] "Create New Candidate": **email should be pulled from the voter list**, not entered manually
- [ ] "Create Candidate": show/pull relevant **voter information fields**, since every candidate originates from the voter list
- [ ] Candidate can view **only their own vote(s)** — in the **Live Dashboard**

## 6. Voter
- [ ] Voter-add flow should match the **format/structure returned by the API** IE member can also come from API.
- [ ] **Voters must NOT be able to see election results** — until result is published ie voting is close even after submiting votes.they will not able to see vote

## 7. Email
- [ ] Email sending should support recipient options: **Election Office**, **Voters**, **Candidates**

---

8. also this not fully role wise in case of observer and auditor oberser is also able to vote and can nominate . also notice section ,election guidelines where not seen in for voter/candidate.election officer.



*Want this broken down further into Django models/API endpoints + Flutter screens, like the other EMS docs?*