(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-NOT-FOUND (err u101))
(define-constant ERR-ALREADY-EXISTS (err u102))
(define-constant ERR-PERMISSION-DENIED (err u103))

;; Data Types
;; ----------

;; Users can be patients, doctors, or pharmacies
(define-data-var users (map principal { role: (string-ascii 10) }) {})

;; Medical records are stored per patient
(define-data-var medical-records (map principal { data: (string-utf8 1000) }) {})

;; Consultations are stored with a unique ID
(define-data-var consultations (map uint {
    patient: principal,
    doctor: principal,
    timestamp: uint,
    notes: (string-utf8 1000)
}) {})

;; Prescriptions are stored with a unique ID
(define-data-var prescriptions (map uint {
    patient: principal,
    doctor: principal,
    pharmacy: (option principal),
    medication: (string-utf8 100),
    quantity: uint,
    timestamp: uint,
    is-dispensed: bool
}) {})

;; Access control: who has access to a patient's data
(define-data-var access-control (map principal (list 100 principal)) {})

;; Counters for IDs
(define-data-var consultation-id-counter uint u0)
(define-data-var prescription-id-counter uint u0)

;; Functions
;; ---------

;; User Registration
(define-public (register (role (string-ascii 10)))
    (let ((sender tx-sender))
        (if (map-get? users sender)
            ERR-ALREADY-EXISTS
            (begin
                (map-set users sender { role: role })
                (ok true)
            )
        )
    )
)

;; Patient grants access to their data
(define-public (grant-access (grantee principal))
    (let ((sender tx-sender))
        (if (is-eq (get role (unwrap! (map-get users sender) ERR-NOT-FOUND)) "patient")
            (begin
                (var-set access-control (map-set access-control sender
                    (cons grantee (default-to '() (map-get access-control sender)))))
                (ok true)
            )
            ERR-NOT-AUTHORIZED
        )
    )
)

;; Patient revokes access to their data
(define-public (revoke-access (grantee principal))
    (let ((sender tx-sender))
        (if (is-eq (get role (unwrap! (map-get users sender) ERR-NOT-FOUND)) "patient")
            (begin
                (var-set access-control (map-set access-control sender
                    (filter (lambda (x) (not (is-eq x grantee)))
                            (default-to '() (map-get access-control sender)))))
                (ok true)
            )
            ERR-NOT-AUTHORIZED
        )
    )
)

;; Schedule a Consultation
(define-public (schedule-consultation (doctor principal) (notes (string-utf8 1000)))
    (let ((sender tx-sender))
        (if (and (is-eq (get role (unwrap! (map-get users sender) ERR-NOT-FOUND)) "patient")
                 (is-eq (get role (unwrap! (map-get users doctor) ERR-NOT-FOUND)) "doctor"))
            (let ((new-id (+ (var-get consultation-id-counter) u1)))
                (var-set consultation-id-counter new-id)
                (map-set consultations new-id {
                    patient: sender,
                    doctor: doctor,
                    timestamp: (block-height),
                    notes: notes
                })
                (ok new-id)
            )
            ERR-NOT-AUTHORIZED
        )
    )
)

;; Doctor records consultation notes
(define-public (record-consultation (consultation-id uint) (notes (string-utf8 1000)))
    (let ((sender tx-sender)
          (consultation (unwrap! (map-get consultations consultation-id) ERR-NOT-FOUND)))
        (if (is-eq (get doctor consultation) sender)
            (begin
                (map-set consultations consultation-id (merge consultation { notes: notes }))
                (ok true)
            )
            ERR-NOT-AUTHORIZED
        )
    )
)

;; Issue a Prescription
(define-public (issue-prescription (patient principal) (medication (string-utf8 100)) (quantity uint))
    (let ((sender tx-sender))
        (if (and (is-eq (get role (unwrap! (map-get users sender) ERR-NOT-FOUND)) "doctor")
                 (map-get? users patient))
            (let ((new-id (+ (var-get prescription-id-counter) u1)))
                (var-set prescription-id-counter new-id)
                (map-set prescriptions new-id {
                    patient: patient,
                    doctor: sender,
                    pharmacy: none,
                    medication: medication,
                    quantity: quantity,
                    timestamp: (block-height),
                    is-dispensed: false
                })
                (ok new-id)
            )
            ERR-NOT-AUTHORIZED
        )
    )
)

;; Patient selects a pharmacy
(define-public (select-pharmacy (prescription-id uint) (pharmacy principal))
    (let ((sender tx-sender)
          (prescription (unwrap! (map-get prescriptions prescription-id) ERR-NOT-FOUND)))
        (if (and (is-eq (get patient prescription) sender)
                 (is-none (get pharmacy prescription))
                 (is-eq (get role (unwrap! (map-get users pharmacy) ERR-NOT-FOUND)) "pharmacy"))
            (begin
                (map-set prescriptions prescription-id (merge prescription { pharmacy: (some pharmacy) }))
                (ok true)
            )
            ERR-NOT-AUTHORIZED
        )
    )
)

;; Pharmacy verifies and dispenses medication
(define-public (dispense-medication (prescription-id uint))
    (let ((sender tx-sender)
          (prescription (unwrap! (map-get prescriptions prescription-id) ERR-NOT-FOUND)))
        (if (and (is-eq (get pharmacy prescription) (some sender))
                 (not (get is-dispensed prescription)))
            (begin
                (map-set prescriptions prescription-id (merge prescription { is-dispensed: true }))
                (ok true)
            )
            ERR-NOT-AUTHORIZED
        )
    )
)

;; Payment Integration (Simplified for demonstration)
(define-public (make-payment (amount uint))
    (begin
        ;; Payment logic would go here
        (ok true)
    )
)

;; Data Access Control
(define-read-only (get-medical-record (patient principal))
    (let ((sender tx-sender)
          (access-list (default-to '() (map-get access-control patient))))
        (if (or (is-eq sender patient) (contains? access-list sender))
            (ok (map-get medical-records patient))
            ERR-PERMISSION-DENIED
        )
    )
)

;; Update Medical Record
(define-public (update-medical-record (data (string-utf8 1000)))
    (let ((sender tx-sender))
        (if (is-eq (get role (unwrap! (map-get users sender) ERR-NOT-FOUND)) "patient")
            (begin
                (map-set medical-records sender { data: data })
                (ok true)
            )
            ERR-NOT-AUTHORIZED
        )
    )
)
