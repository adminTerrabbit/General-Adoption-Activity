global class UserActivityHistoricalBatch implements Database.Batchable<SObject> {
    // Date range: November 1, 2024 until today.
    Date startDate;
    Date endDate;
    
    public UserActivityHistoricalBatch() {
        startDate = Date.newInstance(2024, 11, 1);
        endDate = Date.today();
    }
    
    // Start method queries adoption users.
    public Database.QueryLocator start(Database.BatchableContext BC) {
        return Database.getQueryLocator([
            SELECT Id 
            FROM User 
            WHERE Adoption_Reporting__c = true
        ]);
    }
    
    // Execute method processes a batch of adoption users.
    public void execute(Database.BatchableContext BC, List<SObject> scope) {
        // Get the adoption user Ids.
        Set<Id> adoptionUserIds = new Set<Id>();
        for (User u : (List<User>) scope) {
            adoptionUserIds.add(u.Id);
        }
        
        // Build a list of days in the date range.
        List<Date> dateRange = new List<Date>();
        Integer totalDays = startDate.daysBetween(endDate) + 1;
        for (Integer i = 0; i < totalDays; i++) {
            dateRange.add(startDate.addDays(i));
        }
        
        // Create a map to hold the summary records.
        // The key is a composite string "UserId-Date" (using Date.format() for consistency).
        Map<String, LOCAC__c> summaryMap = new Map<String, LOCAC__c>();
        for (Date d : dateRange) {
            for (Id uid : adoptionUserIds) {
                String key = uid + '-' + d.format();
                summaryMap.put(key, new LOCAC__c(
                    Last_Modified_By__c = uid,
                    Last_Modified_Date__c = d,
                    TasksModifiedLead__c = 0,
                    Tasks_Modified_Opportunity__c = 0,
                    Tasks_Modified_Account__c = 0,
                    Tasks_Modified_Case__c = 0,
                    Tasks_Modified_Contact__c = 0,
                    Tasks_Modified_Unrelated__c = 0,
                    Tasks_Completed_Contact__c = 0,
                    Tasks_Completed_Case__c = 0,
                    Tasks_Completed_Account__c = 0,
                    Tasks_Completed_Lead__c = 0,
                    Tasks_Completed_Opportunity__c = 0,
                    Tasks_Completed_Unrelated__c = 0,
                    Modified_Case__c = 0,
                    Modified_Contact__c = 0,
                    Modified_Account__c = 0,
                    Modified_Lead__c = 0,
                    Modified_Opportunity__c = 0
                ));
            }
        }
        
        // Define a date range filter for queries: from startDate to the end of 'endDate'
        Date queryEndDate = endDate.addDays(1);
        
        // ------------------------------
        // Aggregate Modified Records
        // ------------------------------
        // Modified Leads
        List<AggregateResult> leadResults = [
            SELECT LastModifiedById, DAY_ONLY(LastModifiedDate) day, COUNT(Id) cnt
            FROM Lead
            WHERE LastModifiedById IN :adoptionUserIds 
              AND LastModifiedDate >= :startDate 
              AND LastModifiedDate < :queryEndDate
            GROUP BY LastModifiedById, DAY_ONLY(LastModifiedDate)
        ];
        updateSummaryMap(summaryMap, leadResults, 'Modified_Lead__c', false);
        
        // Modified Opportunities
        List<AggregateResult> oppResults = [
            SELECT LastModifiedById, DAY_ONLY(LastModifiedDate) day, COUNT(Id) cnt
            FROM Opportunity
            WHERE LastModifiedById IN :adoptionUserIds 
              AND LastModifiedDate >= :startDate 
              AND LastModifiedDate < :queryEndDate
            GROUP BY LastModifiedById, DAY_ONLY(LastModifiedDate)
        ];
        updateSummaryMap(summaryMap, oppResults, 'Modified_Opportunity__c', false);
        
        // Modified Accounts
        List<AggregateResult> accResults = [
            SELECT LastModifiedById, DAY_ONLY(LastModifiedDate) day, COUNT(Id) cnt
            FROM Account
            WHERE LastModifiedById IN :adoptionUserIds 
              AND LastModifiedDate >= :startDate 
              AND LastModifiedDate < :queryEndDate
            GROUP BY LastModifiedById, DAY_ONLY(LastModifiedDate)
        ];
        updateSummaryMap(summaryMap, accResults, 'Modified_Account__c', false);
        
        // Modified Cases
        List<AggregateResult> caseResults = [
            SELECT LastModifiedById, DAY_ONLY(LastModifiedDate) day, COUNT(Id) cnt
            FROM Case
            WHERE LastModifiedById IN :adoptionUserIds 
              AND LastModifiedDate >= :startDate 
              AND LastModifiedDate < :queryEndDate
            GROUP BY LastModifiedById, DAY_ONLY(LastModifiedDate)
        ];
        updateSummaryMap(summaryMap, caseResults, 'Modified_Case__c', false);
        
        // Modified Contacts
        List<AggregateResult> contactResults = [
            SELECT LastModifiedById, DAY_ONLY(LastModifiedDate) day, COUNT(Id) cnt
            FROM Contact
            WHERE LastModifiedById IN :adoptionUserIds 
              AND LastModifiedDate >= :startDate 
              AND LastModifiedDate < :queryEndDate
            GROUP BY LastModifiedById, DAY_ONLY(LastModifiedDate)
        ];
        updateSummaryMap(summaryMap, contactResults, 'Modified_Contact__c', false);
        
        // ------------------------------
        // Aggregate Tasks Completed
        // ------------------------------
        // Completed Tasks for Account, Opportunity, Case (using WhatId)
        List<AggregateResult> taskCompletedAOC = [
            SELECT OwnerId, DAY_ONLY(CompletedDateTime) day, COUNT(Id) cnt, WhatId
            FROM Task
            WHERE CompletedDateTime >= :startDate 
              AND CompletedDateTime < :queryEndDate
              AND OwnerId IN :adoptionUserIds 
              AND WhatId != null 
              AND Status = 'Completed'
            GROUP BY OwnerId, DAY_ONLY(CompletedDateTime), WhatId
        ];
        for (AggregateResult ar : taskCompletedAOC) {
            Date d = (Date) ar.get('day');
            Id ownerId = (Id) ar.get('OwnerId');
            Integer count = (Integer) ar.get('cnt');
            Id whatId = (Id) ar.get('WhatId');
            if (whatId != null) {
                Schema.SObjectType sobjType = whatId.getSObjectType();
                if (sobjType == Case.sObjectType) {
                    updateSummaryMapField(summaryMap, ownerId, d, 'Tasks_Completed_Case__c', count);
                } else if (sobjType == Opportunity.sObjectType) {
                    updateSummaryMapField(summaryMap, ownerId, d, 'Tasks_Completed_Opportunity__c', count);
                } else if (sobjType == Account.sObjectType) {
                    updateSummaryMapField(summaryMap, ownerId, d, 'Tasks_Completed_Account__c', count);
                }
            }
        }
        
        // Completed Tasks for Lead and Contact (using WhoId)
        List<AggregateResult> taskCompletedLC = [
            SELECT OwnerId, DAY_ONLY(CompletedDateTime) day, COUNT(Id) cnt, WhoId
            FROM Task
            WHERE CompletedDateTime >= :startDate 
              AND CompletedDateTime < :queryEndDate
              AND OwnerId IN :adoptionUserIds 
              AND WhoId != null
              AND WhatId = null 
              AND Status = 'Completed'
            GROUP BY OwnerId, DAY_ONLY(CompletedDateTime), WhoId
        ];
        for (AggregateResult ar : taskCompletedLC) {
            Date d = (Date) ar.get('day');
            Id ownerId = (Id) ar.get('OwnerId');
            Integer count = (Integer) ar.get('cnt');
            Id whoId = (Id) ar.get('WhoId');
            if (whoId != null) {
                Schema.SObjectType sobjType = whoId.getSObjectType();
                if (sobjType == Case.sObjectType) {
                    updateSummaryMapField(summaryMap, ownerId, d, 'Tasks_Completed_Case__c', count);
                } else if (sobjType == Contact.sObjectType) {
                    updateSummaryMapField(summaryMap, ownerId, d, 'Tasks_Completed_Contact__c', count);
                } else if (sobjType == Opportunity.sObjectType) {
                    updateSummaryMapField(summaryMap, ownerId, d, 'Tasks_Completed_Opportunity__c', count);
                } else if (sobjType == Account.sObjectType) {
                    updateSummaryMapField(summaryMap, ownerId, d, 'Tasks_Completed_Account__c', count);
                } else if (sobjType == Lead.sObjectType) {
                    updateSummaryMapField(summaryMap, ownerId, d, 'Tasks_Completed_Lead__c', count);
                }
            }
        }

        // add code for TaskCompletedUnrelated
        List<AggregateResult> taskCompletedUnrelated = [
            SELECT OwnerId, DAY_ONLY(CompletedDateTime) day, COUNT(Id) cnt
            FROM Task
            WHERE CompletedDateTime >= :startDate 
              AND CompletedDateTime < :queryEndDate
              AND OwnerId IN :adoptionUserIds 
              AND WhatId = null 
              AND WhoId = null
              AND Status = 'Completed'
            GROUP BY OwnerId, DAY_ONLY(CompletedDateTime)
        ];
        for (AggregateResult ar : taskCompletedUnrelated) {
            Date d = (Date) ar.get('day');
            Id ownerId = (Id) ar.get('OwnerId');
            Integer count = (Integer) ar.get('cnt');
            updateSummaryMapField(summaryMap, ownerId, d, 'Tasks_Completed_Unrelated__c', count);
        }
        
        // ------------------------------
        // Aggregate Tasks Modified
        // ------------------------------
        // Modified Tasks for Account, Opportunity, Case (using WhatId)
        List<AggregateResult> taskModifiedAOC = [
            SELECT LastModifiedById, DAY_ONLY(LastModifiedDate) day, COUNT(Id) cnt, WhatId
            FROM Task
            WHERE LastModifiedById IN :adoptionUserIds 
              AND LastModifiedDate >= :startDate 
              AND LastModifiedDate < :queryEndDate
              AND Status != 'Completed' 
              AND WhatId != null
            GROUP BY LastModifiedById, DAY_ONLY(LastModifiedDate), WhatId
        ];
        for (AggregateResult ar : taskModifiedAOC) {
            Date d = (Date) ar.get('day');
            Id userId = (Id) ar.get('LastModifiedById');
            Integer count = (Integer) ar.get('cnt');
            Id whatId = (Id) ar.get('WhatId');
            if (whatId != null) {
                Schema.SObjectType sobjType = whatId.getSObjectType();
                if (sobjType == Case.sObjectType) {
                    updateSummaryMapField(summaryMap, userId, d, 'Tasks_Modified_Case__c', count);
                } else if (sobjType == Opportunity.sObjectType) {
                    updateSummaryMapField(summaryMap, userId, d, 'Tasks_Modified_Opportunity__c', count);
                } else if (sobjType == Account.sObjectType) {
                    updateSummaryMapField(summaryMap, userId, d, 'Tasks_Modified_Account__c', count);
                }
            }
        }
        
        // Modified Tasks for Lead and Contact (using WhoId)
        List<AggregateResult> taskModifiedLC = [
            SELECT LastModifiedById, DAY_ONLY(LastModifiedDate) day, COUNT(Id) cnt, WhoId
            FROM Task
            WHERE LastModifiedById IN :adoptionUserIds 
              AND LastModifiedDate >= :startDate 
              AND LastModifiedDate < :queryEndDate
              AND Status != 'Completed' 
              AND WhoId != null
              AND WhatId = null
            GROUP BY LastModifiedById, DAY_ONLY(LastModifiedDate), WhoId
        ];
        for (AggregateResult ar : taskModifiedLC) {
            Date d = (Date) ar.get('day');
            Id userId = (Id) ar.get('LastModifiedById');
            Integer count = (Integer) ar.get('cnt');
            Id whoId = (Id) ar.get('WhoId');
            if (whoId != null) {
                Schema.SObjectType sobjType = whoId.getSObjectType();
                if (sobjType == Case.sObjectType) {
                    updateSummaryMapField(summaryMap, userId, d, 'Tasks_Modified_Case__c', count);
                } else if (sobjType == Contact.sObjectType) {
                    updateSummaryMapField(summaryMap, userId, d, 'Tasks_Modified_Contact__c', count);
                } else if (sobjType == Opportunity.sObjectType) {
                    updateSummaryMapField(summaryMap, userId, d, 'Tasks_Modified_Opportunity__c', count);
                } else if (sobjType == Account.sObjectType) {
                    updateSummaryMapField(summaryMap, userId, d, 'Tasks_Modified_Account__c', count);
                } else if (sobjType == Lead.sObjectType) {
                    updateSummaryMapField(summaryMap, userId, d, 'TasksModifiedLead__c', count);
                }
            }
        }

        // Add code for task modified unrelated
        List<AggregateResult> taskModifiedUnrelated = [
            SELECT LastModifiedById, DAY_ONLY(LastModifiedDate) day, COUNT(Id) cnt
            FROM Task
            WHERE LastModifiedById IN :adoptionUserIds 
              AND LastModifiedDate >= :startDate 
              AND LastModifiedDate < :queryEndDate
              AND Status != 'Completed'
              AND WhatId = null 
              AND WhoId = null
            GROUP BY LastModifiedById, DAY_ONLY(LastModifiedDate)
        ];
        for (AggregateResult ar : taskModifiedUnrelated) {
            Date d = (Date) ar.get('day');
            Id userId = (Id) ar.get('LastModifiedById');
            Integer count = (Integer) ar.get('cnt');
            updateSummaryMapField(summaryMap, userId, d, 'Tasks_Modified_Unrelated__c', count);
        }
        
        // Upsert (or insert) all the summary records in bulk.
        // (Consider using Database.upsert if you have external ids defined on LOCAC__c.)
        insert summaryMap.values();
    }
    
    // Helper method to update the summaryMap from aggregate results.
    // If isTaskCompleted is true, we use OwnerId; otherwise we use LastModifiedById.
    private void updateSummaryMap(Map<String, LOCAC__c> summaryMap, List<AggregateResult> results, String field, Boolean isTaskCompleted) {
        for (AggregateResult ar : results) {
            Date d = (Date) ar.get('day');
            Id userId;
            if (isTaskCompleted) {
                userId = (Id) ar.get('OwnerId');
            } else {
                userId = (Id) ar.get('LastModifiedById');
            }
            Integer count = (Integer) ar.get('cnt');
            updateSummaryMapField(summaryMap, userId, d, field, count);
        }
    }
    
    // Helper method to update a specific field in a summary record.
    public void updateSummaryMapField(Map<String, LOCAC__c> summaryMap, Id userId, Date d, String field, Integer count) {
        String key = userId + '-' + d.format();
        if (summaryMap.containsKey(key)) {
            LOCAC__c summary = summaryMap.get(key);
            if (field == 'Modified_Lead__c') summary.Modified_Lead__c = count;
            else if (field == 'Modified_Opportunity__c') summary.Modified_Opportunity__c = count;
            else if (field == 'Modified_Account__c') summary.Modified_Account__c = count;
            else if (field == 'Modified_Case__c') summary.Modified_Case__c = count;
            else if (field == 'Modified_Contact__c') summary.Modified_Contact__c = count;
            else if (field == 'TasksModifiedLead__c') summary.TasksModifiedLead__c += count;
            else if (field == 'Tasks_Modified_Opportunity__c') summary.Tasks_Modified_Opportunity__c += count;
            else if (field == 'Tasks_Modified_Account__c') summary.Tasks_Modified_Account__c += count;
            else if (field == 'Tasks_Modified_Case__c') summary.Tasks_Modified_Case__c += count;
            else if (field == 'Tasks_Modified_Contact__c') summary.Tasks_Modified_Contact__c += count;
            else if (field == 'Tasks_Modified_Unrelated__c') summary.Tasks_Modified_Unrelated__c += count;
            else if (field == 'Tasks_Completed_Lead__c') summary.Tasks_Completed_Lead__c += count;
            else if (field == 'Tasks_Completed_Opportunity__c') summary.Tasks_Completed_Opportunity__c += count;
            else if (field == 'Tasks_Completed_Account__c') summary.Tasks_Completed_Account__c += count;
            else if (field == 'Tasks_Completed_Case__c') summary.Tasks_Completed_Case__c += count;
            else if (field == 'Tasks_Completed_Contact__c') summary.Tasks_Completed_Contact__c += count;
            else if (field == 'Tasks_Completed_Unrelated__c') summary.Tasks_Completed_Unrelated__c += count;
            summaryMap.put(key, summary);
        }
    }
    
    public void finish(Database.BatchableContext BC) {
        // Post-processing logic can be added here if needed.
    }
}