/**
 * DiabetesCareAssessment
 *
 * Apex class for assessing diabetes care based on HbA1c values and program enrollment.
 * Designed to be invocable from Flow and other automation tools.
 *
 * Overview:
 * - Queries latest finalized HbA1c CareObservation per patient using the HbA1c CodeSet
 * - Determines if patient is enrolled in an active Diabetes care program
 * - Categorizes risk based on HbA1c value:
 *   - < 7.0: Well Controlled
 *   - 7.0 - < 9.0: Needs Attention
 *   - >= 9.0: High Risk/Urgent
 *   - No data: No Data Available
 *
 * Security:
 * - with sharing to enforce sharing rules
 * - Read-only SOQL queries, no DML
 *
 * @author Agentforce
 */
public with sharing class DiabetesCareAssessment {

    /**
     * Wrapper for invocable input.
     */
    public class AssessmentRequest {
        /**
         * The Salesforce ID of the patient/account to assess.
         */
        @InvocableVariable(label='Patient Id' description='The Salesforce Id of the patient/account to assess' required=true)
        public Id patientId;

        /**
         * Number of days to look back for observations (currently not used).
         */
        @InvocableVariable(label='Days Lookback' description='Number of days to look back for observations (currently not used in implementation)' required=false)
        public Integer daysLookback;

        public AssessmentRequest() {}

        public AssessmentRequest(Id patientId, Integer daysLookback) {
            this.patientId = patientId;
            this.daysLookback = daysLookback;
        }
    }

    /**
     * Wrapper for invocable output.
     */
    public class AssessmentResult {
        /**
         * The Salesforce ID of the patient that was assessed.
         */
        @InvocableVariable(label='Patient Id' description='The Salesforce Id of the patient that was assessed' required=false)
        public Id patientId;

        /**
         * The latest HbA1c value found for the patient (null if no observation found).
         */
        @InvocableVariable(label='HbA1c Value' description='The latest HbA1c value found for the patient (null if no observation found)' required=false)
        public Decimal hba1cValue;

        /**
         * Categorized risk level based on HbA1c value.
         */
        @InvocableVariable(label='Risk Category' description='Categorized risk level based on HbA1c value' required=false)
        public String riskCategory;

        /**
         * Indicates whether the patient is enrolled in an active Diabetes care program.
         */
        @InvocableVariable(label='Is In Diabetes Program' description='Indicates whether the patient is enrolled in an active Diabetes care program' required=false)
        public Boolean isInDiabetesProgram;

        /**
         * Contains error message if processing failed for this patient (null if successful).
         */
        @InvocableVariable(label='Error Message' description='Contains error message if processing failed for this patient (null if successful)' required=false)
        public String errorMessage;

        public AssessmentResult() {}

        public AssessmentResult(Id patientId) {
            this.patientId = patientId;
        }
    }

    /**
     * Invocable entry point. Assesses patient diabetes care based on HbA1c values and program enrollment.
     *
     * @param requests list of AssessmentRequest
     * @return List of AssessmentResult, one per input patient id
     */
    @InvocableMethod(label='Assess Patient' description='Assesses patient diabetes care based on HbA1c values and program enrollment')
    public static List<AssessmentResult> assessPatient(List<AssessmentRequest> requests) {
        List<AssessmentResult> results = new List<AssessmentResult>();

        // 1. Input validation
        if (requests == null || requests.isEmpty()) {
            return results; // empty
        }

        // 2. Extract patient Ids and map to request
        Set<Id> patientIds = new Set<Id>();
        Map<Id, AssessmentRequest> requestByPatientId = new Map<Id, AssessmentRequest>();
        for (AssessmentRequest req : requests) {
            if (req != null && req.patientId != null) {
                patientIds.add(req.patientId);
                requestByPatientId.put(req.patientId, req);
            }
        }

        if (patientIds.isEmpty()) {
            return results;
        }

        // 3. HbA1c CodeSet Lookup
        Id hba1cCodeSetId = getHbA1cCodeSetId();
        if (hba1cCodeSetId == null) {
            // error for all patients
            for (Id pid : patientIds) {
                AssessmentResult res = new AssessmentResult(pid);
                res.errorMessage = 'HbA1c CodeSet not found in the system';
                res.riskCategory = 'No Data Available';
                res.isInDiabetesProgram = false;
                results.add(res);
            }
            return results;
        }

        // 4. Data retrieval
        Map<Id, CareObservation> latestObsByPatient = getLatestHbA1cObservations(patientIds, hba1cCodeSetId);
        Map<Id, Boolean> isInProgramByPatient = checkActiveDiabetesPrograms(patientIds);

        // 5. Result processing
        for (Id pid : patientIds) {
            AssessmentResult res = new AssessmentResult(pid);
            try {
                CareObservation obs = latestObsByPatient.get(pid);
                if (obs != null && obs.ObservedValueNumerator != null) {
                    res.hba1cValue = obs.ObservedValueNumerator;
                    Decimal val = res.hba1cValue;

                    if (val < 7.0) {
                        res.riskCategory = 'Well Controlled';
                    } else if (val >= 7.0 && val < 9.0) {
                        res.riskCategory = 'Needs Attention';
                    } else {
                        res.riskCategory = 'High Risk/Urgent';
                    }
                } else {
                    res.riskCategory = 'No Data Available';
                }

                res.isInDiabetesProgram = isInProgramByPatient.containsKey(pid) ? isInProgramByPatient.get(pid) : false;
            } catch (Exception ex) {
                res.errorMessage = 'Error processing patient ' + String.valueOf(pid) + ': ' + ex.getMessage();
            }
            results.add(res);
        }

        // 6. Return
        return results;
    }

    /**
     * Retrieves the Salesforce ID of the CodeSet record named 'HbA1c'.
     *
     * @return Id of HbA1c CodeSet or null if not found
     */
    private static Id getHbA1cCodeSetId() {
        // LIMIT 1 for selectivity and governor limits
        List<CodeSet> cs = [
            SELECT Id
            FROM CodeSet
            WHERE Name = 'HbA1c'
            LIMIT 1
        ];
        return cs.isEmpty() ? null : cs[0].Id;
    }

    /**
     * Retrieves the most recent finalized HbA1c CareObservation for each patient.
     *
     * @param patientIds Set of patient/account IDs
     * @param hba1cCodeSetId Id of the HbA1c CodeSet
     * @return Map of Patient Id to most recent CareObservation
     */
    private static Map<Id, CareObservation> getLatestHbA1cObservations(Set<Id> patientIds, Id hba1cCodeSetId) {
        Map<Id, CareObservation> result = new Map<Id, CareObservation>();
        if (patientIds == null || patientIds.isEmpty() || hba1cCodeSetId == null) {
            return result;
        }

        // Query most recent first, then take the first per patient
        for (CareObservation co : [
            SELECT Id, ObservedSubjectId, ObservedValueNumerator, EffectiveDateTime
            FROM CareObservation
            WHERE CodeId = :hba1cCodeSetId
              AND ObservedSubjectId IN :patientIds
              AND ObservationStatus = 'Final'
              AND ObservedValueType = 'Quantity'
              AND ObservedValueNumerator != null
            ORDER BY EffectiveDateTime DESC NULLS LAST
            LIMIT 1000
        ]) {
            if (!result.containsKey(co.ObservedSubjectId)) {
                result.put(co.ObservedSubjectId, co);
            }
        }
        return result;
    }

    /**
     * Determines which patients are enrolled in active Diabetes care programs.
     *
     * @param patientIds Set of patient/account IDs
     * @return Map of Patient Id to boolean indicating active enrollment
     */
    private static Map<Id, Boolean> checkActiveDiabetesPrograms(Set<Id> patientIds) {
        Map<Id, Boolean> enrolledMap = new Map<Id, Boolean>();
        if (patientIds == null || patientIds.isEmpty()) {
            return enrolledMap;
        }
        // Initialize defaults to false
        for (Id pid : patientIds) {
            enrolledMap.put(pid, false);
        }

        // Subquery to find Diabetes programs by name
        Set<Id> diabetesProgramIds = new Set<Id>();
        for (CareProgram cp : [
            SELECT Id
            FROM CareProgram
            WHERE Name LIKE '%Diabetes%'
            LIMIT 1000
        ]) {
            diabetesProgramIds.add(cp.Id);
        }
        if (diabetesProgramIds.isEmpty()) {
            return enrolledMap;
        }

        for (CareProgramEnrollee cpe : [
            SELECT Id, CareProgramId, AccountId, Status
            FROM CareProgramEnrollee
            WHERE AccountId IN :patientIds
              AND Status = 'Active'
              AND CareProgramId IN :diabetesProgramIds
            LIMIT 5000
        ]) {
            if (cpe.AccountId != null) {
                enrolledMap.put(cpe.AccountId, true);
            }
        }
        return enrolledMap;
    }
}
