public class DiabetesCareObservationTriggerHandler {
    
    public static void handleAfterInsert(List<CareObservation> newObservations) {
        processObservations(newObservations);
    }
    
    public static void handleAfterUpdate(List<CareObservation> newObservations) {
        processObservations(newObservations);
    }
    
    private static void processObservations(List<CareObservation> newObservations) {
        // Get thresholds from Custom Metadata (cached automatically)
        Diabetes_Threshold__mdt thresholds = [SELECT Target_Percentage__c, Warning_Percentage__c, Critical_Percentage__c
                                              FROM Diabetes_Threshold__mdt
                                              WHERE DeveloperName = 'Standard_Diabetes_Thresholds'
                                              LIMIT 1];

        List<Task> tasksToCreate = new List<Task>();
        Set<Id> observationIds = new Set<Id>();
        Set<Id> codeIds = new Set<Id>();
        Map<Id, Decimal> observationHbA1cMap = new Map<Id, Decimal>();

        // First pass: collect Code IDs to query
        for(CareObservation obs : newObservations) {
            if(obs.CodeId != null) {
                codeIds.add(obs.CodeId);
            }
        }

        // Query CodeSet records to get code names
        Map<Id, CodeSet> codeMap = new Map<Id, CodeSet>(
            [SELECT Id, Name FROM CodeSet WHERE Id IN :codeIds]
        );

        // Second pass: collect observation IDs and HbA1c values for bulk processing
        for(CareObservation obs : newObservations) {
            CodeSet code = codeMap.get(obs.CodeId);
            String codeName = code != null ? code.Name : null;

            System.debug('Code Name: ' + codeName);
            // Only process finalized HbA1c observations with valid data
            if(codeName == 'HbA1c' &&
               obs.ObservationStatus == 'Final' &&
               obs.ObservedValueType == 'Quantity' &&
               obs.ObservedValueNumerator != null &&
               obs.ObservedValueNumerator >= thresholds.Warning_Percentage__c &&
               obs.ObservedSubjectId != null) {

                observationIds.add(obs.Id);
                observationHbA1cMap.put(obs.Id, obs.ObservedValueNumerator);
            }
        }

        if(!observationIds.isEmpty()) {
            // FIX BUG 1: Query OUTSIDE the loop for all observations at once
            Map<Id, Task> existingTasksMap = new Map<Id, Task>();
            List<Task> existingTasks = [SELECT Id, WhatId FROM Task
                                       WHERE WhatId IN :observationIds
                                       AND Subject LIKE '%HbA1c Follow-up%'
                                       AND Status != 'Completed'
                                       AND CreatedDate = LAST_N_DAYS:30];
            
            // Create a map for quick lookup
            for(Task t : existingTasks) {
                existingTasksMap.put(t.WhatId, t);
            }

            for(Id observationId : observationIds) {
                // Check if task already exists for this observation
                if(!existingTasksMap.containsKey(observationId)) {
                    Decimal hba1cValue = observationHbA1cMap.get(observationId);

                    Task followUpTask = new Task();
                    followUpTask.Subject = 'HbA1c Follow-up Required - ' + Date.today().format();
                    followUpTask.WhatId = observationId;
                    
                    // FIX BUG 2: Add required ActivityDate field
                    if(hba1cValue >= thresholds.Critical_Percentage__c) {
                        followUpTask.Priority = 'High';
                        followUpTask.ActivityDate = Date.today().addDays(1); // Urgent: next day
                    } else if(hba1cValue >= thresholds.Warning_Percentage__c) {
                        followUpTask.Priority = 'Normal';
                        followUpTask.ActivityDate = Date.today().addDays(7); // Normal: one week
                    } else {
                        followUpTask.Priority = 'Low';
                        followUpTask.ActivityDate = Date.today().addDays(14); // Low: two weeks
                    }

                    followUpTask.Status = 'Not Started';
                    followUpTask.Type = 'Call';

                    // FIX BUG 3: Add null check before string concatenation
                    if(hba1cValue != null) {
                        followUpTask.Description = 'Patient has new HbA1c level of ' +
                                                 hba1cValue + '%. Schedule follow-up appointment to review ' +
                                                 'diabetes management plan and medication adherence. ' +
                                                 'Thresholds: Target <' + thresholds.Target_Percentage__c +
                                                 '%, Warning ≥' + thresholds.Warning_Percentage__c +
                                                 '%, Critical ≥' + thresholds.Critical_Percentage__c + '%.';
                    }

                    // FIX BUG 4: Add to list instead of inserting in loop
                    tasksToCreate.add(followUpTask);
                }
            }
            
            // Bulk insert all tasks at once
            if(!tasksToCreate.isEmpty()) {
                insert tasksToCreate;
            }
        }
    }
}