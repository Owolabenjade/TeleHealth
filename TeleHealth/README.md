# Decentralized Telemedicine and Prescription Management Platform

This Clarity smart contract enables secure telemedicine consultations, prescription issuance, and patient data management on a decentralized blockchain platform. It supports distinct roles for patients, doctors, and pharmacies, manages consultation and prescription records, and facilitates secure, token-based payments, all while enforcing role-based access controls and data privacy.

## Features

- **Role-based Access Control:** Three primary roles (Patient, Doctor, Pharmacy) to enable secure, role-based actions.
- **Consultations & Prescriptions:** Secure consultation scheduling, note-taking, and prescription issuance and dispensing.
- **Data Management:** Off-chain patient medical records are managed with secure access control.
- **Token-Based Payments:** Integration with SIP-010 fungible token standard for transaction-based payments.
- **Rate-Limiting:** Limits the number of consultations per doctor to reduce spam or abuse.

## Roles

1. **Patient:** Can schedule consultations, manage access to their medical records, and select pharmacies for prescriptions.
2. **Doctor:** Authorized to conduct consultations, record notes, and issue prescriptions.
3. **Pharmacy:** Dispenses prescribed medication after validation.

## Data Structures

- **Users:** Stores user roles and public keys for patients, doctors, and pharmacies.
- **Medical Records:** Off-chain references for patient records (e.g., hashes of data).
- **Consultations:** Stores consultation details between patients and doctors.
- **Prescriptions:** Tracks prescriptions issued by doctors, selected pharmacies, and dispensing status.
- **Access Control:** Patient-granted access to their medical records.
- **Payments:** Logs transaction records between participants using SIP-010 tokens.

## Public Functions

### User Registration

- `register(role, public-key)`: Registers a user with a specific role and public key.
- **Roles:** `patient`, `doctor`, `pharmacy`.

### Consultation & Prescription Management

- `schedule-consultation(doctor)`: Patient schedules a consultation with a doctor.
- `record-consultation-notes(consultation-id, notes-hash)`: Doctor records notes for a consultation.
- `issue-prescription(patient, medication, quantity)`: Doctor issues a prescription for the patient.
- `select-pharmacy(prescription-id, pharmacy)`: Patient selects a pharmacy to dispense their prescription.
- `dispense-medication(prescription-id)`: Pharmacy dispenses prescribed medication to the patient.

### Access Control

- `grant-access(grantee)`: Patient grants access to their medical records to an authorized user.
- `revoke-access(grantee)`: Patient revokes access to their medical records.

### Payment

- `make-payment(ft, amount, recipient)`: Facilitates token-based payments between users.

### Data Management

- `update-medical-record(data-hash)`: Patient updates their off-chain medical record reference.
- `get-medical-record(patient)`: Authorized users retrieve a patient’s medical record.

## Error Codes

- **ERR-NOT-AUTHORIZED (100):** Unauthorized action by the user.
- **ERR-NOT-FOUND (101):** Resource not found.
- **ERR-ALREADY-EXISTS (102):** Entity already exists.
- **ERR-PERMISSION-DENIED (103):** Access denied to the resource.
- **ERR-INVALID-ROLE (104):** Invalid user role.
- **ERR-INVALID-INPUT (105):** Invalid function input.
- **ERR-OPERATION-FAILED (106):** Generic operation failure.
- **ERR-NOT-PATIENT (107):** User is not a registered patient.
- **ERR-NOT-DOCTOR (108):** User is not a registered doctor.
- **ERR-NOT-PHARMACY (109):** User is not a registered pharmacy.
- **ERR-RATE-LIMIT (111):** Rate limit reached.
- **ERR-EXPIRED (112):** Prescription or consultation expired.

## Installation

1. Deploy the smart contract to a Clarity-compatible blockchain.
2. Configure the fungible token contract as `payment-token-contract` for handling payments.

## Usage Example

### Scenario: Patient Scheduling a Consultation and Filling a Prescription

1. **Registration:**
   - A patient, doctor, and pharmacy each call `register(role, public-key)` with their respective roles.
   
2. **Scheduling a Consultation:**
   - The patient calls `schedule-consultation(doctor)` to schedule a consultation with a registered doctor. A consultation ID is returned.
   
3. **Recording Consultation Notes:**
   - After the consultation, the doctor records notes by calling `record-consultation-notes(consultation-id, notes-hash)`.
   
4. **Issuing a Prescription:**
   - The doctor issues a prescription by calling `issue-prescription(patient, medication, quantity)`.
   
5. **Selecting a Pharmacy:**
   - The patient calls `select-pharmacy(prescription-id, pharmacy)` to assign a pharmacy to the prescription.
   
6. **Dispensing Medication:**
   - The pharmacy calls `dispense-medication(prescription-id)` to confirm dispensing the medication.

7. **Payment:**
   - The patient makes a payment using `make-payment(ft, amount, recipient)` with the SIP-010 token.

## Security Measures

- **Role Validation:** Functions require the correct user role to execute specific actions, preventing unauthorized access.
- **Access Control:** Only authorized entities (as set by the patient) can access medical records.
- **Rate-Limiting:** Limits the number of consultations per doctor to prevent spam.
- **Error Handling:** Detailed error codes help diagnose issues, preventing unchecked execution paths.