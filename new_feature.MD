# Election / Ballot System Requirements

## 1. Ballot – Full Width

* The ballot should be displayed in **full width for all voters**.
* The ballot should use the **complete available screen width**.
* For venue-based voting, the ballot should be **completely full-screen/full-width**.
* The **“Local Host”** section at the top should **not be displayed** on the venue ballot.

## 2. Notice Board

* The **stamp should be positioned on the left side**.
* The notice content should be **center aligned**.
* If the notice is long and extends to multiple pages, the **signature should be displayed on every page**.

## 3. Polling Station Initialization

* When a polling station is initialized, the system should generate a **unique PIN for each voter**.
* Each voter must have their own unique PIN.
* Duplicate PINs should not be allowed.
* The PIN should be used by the voter to access the voting process.

## 4. Election Settings – Party / Panel

Election creation/edit settings should include:

* **Party: Enable / Disable**
* **Panel: Enable / Disable**

If Party or Panel is disabled, it should **not be displayed in the voting interface**.

## 5. Voting – Symbol / Photo

The voting interface should support displaying a **symbol and/or photo**, based on the election configuration.

Election settings should include:

* **Symbol: Enable / Disable**
* Symbol should be an **optional setting**.
* If Symbol is enabled, the relevant **symbol should be displayed during voting**.
* If the election is configured to display a candidate/photo, the **photo should be displayed accordingly**.
* If Symbol is disabled, the symbol should not be displayed.

At the bottom of the voting interface, display the relevant:

* **Party**
* **Panel**

according to the election settings.

## 6. Symbol – Samānupātik (Proportional) Election

* The **Symbol option should be specifically available for Samānupātik (Proportional) elections**.
* While creating an election, if **Samānupātik / Proportional** is selected, provide:

  * **Symbol: Enable / Disable**
* If Symbol is enabled, the assigned **party/panel/candidate symbol** should be displayed during voting.
* If Symbol is disabled, the symbol should not be displayed.
* Symbol configuration should be **election-specific** and should not automatically apply to every election.

## 7. Partial Election

While creating an election, provide:

* **Partial Election: Yes / No**

If **Partial Election = Yes**:

* Voter separation should be enabled.
* The system should identify **which branch each voter belongs to**.
* Voters should be separated according to their **branch**.
* Each voter should only be shown/allowed to participate in the relevant election or voting group applicable to their branch.

## 8. Voting System – FPTP / Samānupātik

While creating an election, provide a **Voting System / Election Type** option.

Available options should include:

* **First-Past-the-Post (FPTP)**
* **Samānupātik (Proportional Representation)**

### 8.1 First-Past-the-Post (FPTP)

* The candidate receiving the highest number of valid votes should be declared elected.
* The system should support the configured number of seats/candidates.
* Results should show:

  * Total votes
  * Valid votes
  * Invalid votes
  * Vote count per candidate
  * Elected candidate(s)

### 8.2 Samānupātik (Proportional Representation)

* The system should support **party/panel-based proportional voting**.
* The administrator should be able to configure the **number of available seats**.
* The system should calculate the **total votes and vote percentage** for each party/panel.
* Seats should be allocated according to the configured **proportional representation rules**.
* The election should allow the administrator to configure the applicable proportional calculation method/rules.

### 8.3 Samānupātik Election Configuration

For a Samānupātik election, the administrator should be able to configure:

* Total number of seats
* Participating parties
* Participating panels, where applicable
* Candidate list
* Symbol, if enabled
* Applicable vote/seat allocation rules
* Any applicable minimum vote threshold

### 8.4 Samānupātik Results

The results should clearly display:

* Total votes received by each party/panel
* Vote percentage
* Total seats available
* Seats allocated to each party/panel
* Elected candidates
* Complete seat-allocation calculation for transparency

## 9. Election-Level Settings

All relevant settings should be configurable **for each individual election**.

Election creation/settings should include, where applicable:

* **Election Type:** FPTP / Samānupātik
* **Party:** Enable / Disable
* **Panel:** Enable / Disable
* **Symbol:** Enable / Disable
* **Partial Election:** Yes / No
* **Branch-wise voter separation**
* **Number of seats**
* **Samānupātik calculation/rules**

The selected settings should control both the **voting interface** and the **result calculation** for that specific election.
