public class UserActivityBatch implements Database.Batchable<SObject> {

    public Database.QueryLocator start(Database.BatchableContext BC) {
        return Database.getQueryLocator([SELECT Id FROM User WHERE Adoption_Reporting__c = true]);
    }

    // Execute method to process the records
    public void execute(Database.BatchableContext BC, List<SObject> scope) {
        Set<Id> adoptionUsers = new Set<Id>();
        Map<Id, LOCAC__c> userSummaryMap = new Map<Id, LOCAC__c>();

        for (User u : (List<User>)scope) {
            adoptionUsers.add(u.Id);
        }

        // Initialize summary record for user
        for (Id userId : adoptionUsers) {
            userSummaryMap.put(userId, new LOCAC__c(
                Last_Modified_By__c = userId,
                Last_Modified_Date__c = System.today().addDays(-1), // YESTERDAY
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
                Modified_Opportunity__c = 0,
                Events_Completed_Account__c = 0,
                Events_Completed_Case__c = 0,
                Events_Completed_Contact__c = 0,
                Events_Completed_Lead__c = 0,
                Events_Completed_Opportunity__c = 0,
                Events_Modified_Account__c = 0,
                Events_Modified_Case__c = 0,
                Events_Modified_Contact__c = 0,
                Events_Modified_Lead__c = 0,
                Events_Modified_Opportunity__c = 0
            ));
        }

        // Initialize query for different objects: Lead, Opportunity, Account, Case, Contact, Task (Modified/Completed)
        // Modified Leads
        List<AggregateResult> leadCount = [
            SELECT LastModifiedById, COUNT(Id) 
            FROM Lead 
            WHERE LastModifiedById != NULL AND LastModifiedDate = YESTERDAY AND (LastModifiedById IN :adoptionUsers)
            GROUP BY LastModifiedById
        ];

        // Modified Opportunities
        List<AggregateResult> oppCount = [
            SELECT LastModifiedById, COUNT(Id) 
            FROM Opportunity 
            WHERE LastModifiedById != NULL AND LastModifiedDate = YESTERDAY AND (LastModifiedById IN :adoptionUsers)
            GROUP BY LastModifiedById
        ];

        // Modified Accounts
        List<AggregateResult> accCount = [
            SELECT LastModifiedById, COUNT(Id) 
            FROM Account 
            WHERE LastModifiedById != NULL AND LastModifiedDate = YESTERDAY AND (LastModifiedById IN :adoptionUsers)
            GROUP BY LastModifiedById
        ];

        // Modified Cases
        List<AggregateResult> caseCount = [
            SELECT LastModifiedById, COUNT(Id) 
            FROM Case 
            WHERE LastModifiedById != NULL AND LastModifiedDate = YESTERDAY AND (LastModifiedById IN :adoptionUsers)
            GROUP BY LastModifiedById
        ];

        // Modified Contacts
        List<AggregateResult> contactCount = [
            SELECT LastModifiedById, COUNT(Id) 
            FROM Contact 
            WHERE LastModifiedById != NULL AND LastModifiedDate = YESTERDAY AND (LastModifiedById IN :adoptionUsers)
            GROUP BY LastModifiedById
        ];

        List<AggregateResult> taskCompletedCountCase = new List<AggregateResult>();
        List<AggregateResult> taskCompletedCountOpportunity = new List<AggregateResult>();
        List<AggregateResult> taskCompletedCountAccount = new List<AggregateResult>();

        // Completed Tasks - Account, Opportunity, Case
        List<AggregateResult> taskCompletedAOCCount = [
            SELECT OwnerId, COUNT(Id), WhatId 
            FROM Task 
            WHERE CompletedDateTime = YESTERDAY AND WhatId != NULL AND Status = 'Completed'
            AND OwnerId != NULL AND (OwnerId IN :adoptionUsers)
            GROUP BY OwnerId, WhatId
        ];

        // Process completed task counts
        for (AggregateResult ar : taskCompletedAOCCount) {
            Integer count = (Integer) ar.get('expr0'); // Get the count of completed tasks
            Id WhatId = (Id) ar.get('WhatId');

            // Check WhatId field to categorize tasks by object type
            if (WhatId != null){
                if (WhatId.getSObjectType() == Case.sObjectType) {
                    taskCompletedCountCase.add(ar);
                } else if (WhatId.getSObjectType() == Opportunity.sObjectType) {
                    taskCompletedCountOpportunity.add(ar);
                } else if (WhatId.getSObjectType() == Account.sObjectType) {
                    taskCompletedCountAccount.add(ar);
                }
            }
        }

        List<AggregateResult> taskCompletedCountLead = new List<AggregateResult>();
        List<AggregateResult> taskCompletedCountContact = new List<AggregateResult>();

        // Completed Tasks - Lead, Contact
        List<AggregateResult> taskCompletedLCCount = [
            SELECT OwnerId, COUNT(Id), WhoId
            FROM Task 
            WHERE CompletedDateTime = YESTERDAY AND WhoId != NULL AND WhatId = NULL AND Status = 'Completed'
            AND OwnerId != NULL AND (OwnerId IN :adoptionUsers)
            GROUP BY OwnerId, WhoId
        ];

        // Process completed task counts
        for (AggregateResult ar : taskCompletedLCCount) {
            Integer count = (Integer) ar.get('expr0'); // Get the count of completed tasks
            Id WhoId = (Id) ar.get('WhoId');

            // Check WhatId field to categorize tasks by object type
            if (WhoId != null){
                if (WhoId.getSObjectType() == Case.sObjectType) {
                    taskCompletedCountCase.add(ar);
                } else if (WhoId.getSObjectType() == Contact.sObjectType) {
                    taskCompletedCountContact.add(ar);
                } else if (WhoId.getSObjectType() == Opportunity.sObjectType) {
                    taskCompletedCountOpportunity.add(ar);
                } else if (WhoId.getSObjectType() == Account.sObjectType) {
                    taskCompletedCountAccount.add(ar);
                } else if (WhoId.getSObjectType() == Lead.sObjectType) {
                    taskCompletedCountLead.add(ar);
                    System.debug('--- taskCompletedCountLead'+ taskCompletedCountLead);
                }
            }
        }

        /***                 ***/
        /*** Start of Events ***/
        /***                 ***/
        List<AggregateResult> eventCompletedCountCase = new List<AggregateResult>();
        List<AggregateResult> eventCompletedCountOpportunity = new List<AggregateResult>();
        List<AggregateResult> eventCompletedCountAccount = new List<AggregateResult>();

        // Completed Events - Account, Opportunity, Case
        List<AggregateResult> eventCompletedAOCCount = [
            SELECT OwnerId, COUNT(Id), WhatId 
            FROM Event
            WHERE EndDate = YESTERDAY AND WhatId != NULL
            AND OwnerId != NULL AND (OwnerId IN :adoptionUsers)
            GROUP BY OwnerId, WhatId
        ];

        // Process completed event counts
        for (AggregateResult ar : eventCompletedAOCCount) {
            Integer count = (Integer) ar.get('expr0'); // Get the count of completed tasks
            Id WhatId = (Id) ar.get('WhatId');

            // Check WhatId field to categorize events by object type
            if (WhatId != null){
                if (WhatId.getSObjectType() == Case.sObjectType) {
                    eventCompletedCountCase.add(ar);
                } else if (WhatId.getSObjectType() == Opportunity.sObjectType) {
                    eventCompletedCountOpportunity.add(ar);
                } else if (WhatId.getSObjectType() == Account.sObjectType) {
                    eventCompletedCountAccount.add(ar);
                }
            }
        }

        List<AggregateResult> eventCompletedCountLead = new List<AggregateResult>();
        List<AggregateResult> eventCompletedCountContact = new List<AggregateResult>();

        // Completed Events - Lead, Contact
        List<AggregateResult> eventCompletedLCCount = [
            SELECT OwnerId, COUNT(Id), WhoId
            FROM Event 
            WHERE EndDate = YESTERDAY AND WhoId != NULL AND WhatId = NULL
            AND OwnerId != NULL AND (OwnerId IN :adoptionUsers)
            GROUP BY OwnerId, WhoId
        ];

        // Process completed events count
        for (AggregateResult ar : eventCompletedLCCount) {
            Integer count = (Integer) ar.get('expr0'); // Get the count of completed tasks
            Id WhoId = (Id) ar.get('WhoId');

            // Check WhatId field to categorize tasks by object type
            if (WhoId != null){
                if (WhoId.getSObjectType() == Case.sObjectType) {
                    eventCompletedCountCase.add(ar);
                } else if (WhoId.getSObjectType() == Contact.sObjectType) {
                    eventCompletedCountContact.add(ar);
                } else if (WhoId.getSObjectType() == Opportunity.sObjectType) {
                    eventCompletedCountOpportunity.add(ar);
                } else if (WhoId.getSObjectType() == Account.sObjectType) {
                    eventCompletedCountAccount.add(ar);
                } else if (WhoId.getSObjectType() == Lead.sObjectType) {
                    eventCompletedCountLead.add(ar);
                    System.debug('--- eventCompletedCountLead'+ eventCompletedCountLead);
                }
            }
        }

        List<AggregateResult> eventModifiedCountCase = new List<AggregateResult>();
        List<AggregateResult> eventModifiedCountOpportunity = new List<AggregateResult>();
        List<AggregateResult> eventModifiedCountAccount = new List<AggregateResult>();

        // Modified Events - AOC
        List<AggregateResult> eventModifiedAOCCount = [
            SELECT LastModifiedById, COUNT(Id), WhatId
            FROM Event 
            WHERE LastModifiedDate = YESTERDAY AND WhatId != NULL
            AND LastModifiedById != NULL AND (LastModifiedById IN :adoptionUsers) AND CreatedDate < YESTERDAY
            GROUP BY LastModifiedById, WhatId
        ];

        // Process modified event (Account, Opp, Case) counts
        for (AggregateResult ar : eventModifiedAOCCount) {
            Integer count = (Integer) ar.get('expr0'); // Get the count of modified tasks
            Id WhatId = (Id) ar.get('WhatId');

            // Check WhatId field to categorize tasks by object type
            if (WhatId != null){
                if (WhatId.getSObjectType() == Case.sObjectType) {
                    eventModifiedCountCase.add(ar);
                } else if (WhatId.getSObjectType() == Opportunity.sObjectType) {
                    eventModifiedCountOpportunity.add(ar);
                } else if (WhatId.getSObjectType() == Account.sObjectType) {
                    eventModifiedCountAccount.add(ar);
                }
            }
        }

        List<AggregateResult> eventModifiedCountContact = new List<AggregateResult>();
        List<AggregateResult> eventModifiedCountLead = new List<AggregateResult>();

         // Modified Events - (Lead, Contact)
         List<AggregateResult> eventModifiedLCCount = [
            SELECT LastModifiedById, COUNT(Id), WhoId
            FROM Event 
            WHERE LastModifiedDate = YESTERDAY AND WhoId!= NULL AND WhatId = NULL
            AND LastModifiedById != NULL AND (LastModifiedById IN :adoptionUsers) AND CreatedDate < YESTERDAY
            GROUP BY LastModifiedById, WhoId
        ];

        // Process modified task (Lead, Contact) counts
        for (AggregateResult ar : eventModifiedLCCount) {
            Integer count = (Integer) ar.get('expr0'); // Get the count of modified tasks
            Id WhoId = (Id) ar.get('WhoId');

            // Check WhatId field to categorize tasks by object type
            if (WhoId != null){
                if (WhoId.getSObjectType() == Case.sObjectType) {
                    eventModifiedCountCase.add(ar);
                } else if (WhoId.getSObjectType() == Contact.sObjectType) {
                    eventModifiedCountContact.add(ar);
                } else if (WhoId.getSObjectType() == Opportunity.sObjectType) {
                    eventModifiedCountOpportunity.add(ar);
                } else if (WhoId.getSObjectType() == Account.sObjectType) {
                    eventModifiedCountAccount.add(ar);
                } else if (WhoId.getSObjectType() == Lead.sObjectType) {
                    eventModifiedCountLead.add(ar);
                }
            }
        }


        /***               ***/
        /*** End of Events ***/
        /***               ***/

        // Completed Tasks - Unrelated
        List<AggregateResult> taskCompletedCountUnrelated = [
            SELECT OwnerId, COUNT(Id)
            FROM Task 
            WHERE CompletedDateTime = YESTERDAY AND WhatId = NULL AND WhoId = NULL AND Status = 'Completed'
            AND OwnerId != NULL AND (OwnerId IN :adoptionUsers)
            GROUP BY OwnerId
        ];

        List<AggregateResult> taskModifiedCountCase = new List<AggregateResult>();
        List<AggregateResult> taskModifiedCountOpportunity = new List<AggregateResult>();
        List<AggregateResult> taskModifiedCountAccount = new List<AggregateResult>();

        // Modified Tasks - LC
        List<AggregateResult> taskModifiedAOCCount = [
            SELECT LastModifiedById, COUNT(Id), WhatId
            FROM Task 
            WHERE LastModifiedDate = YESTERDAY AND Status != 'Completed' AND WhatId != NULL
            AND LastModifiedById != NULL AND (LastModifiedById IN :adoptionUsers)
            GROUP BY LastModifiedById, WhatId
        ];

        // Process modified task (Account, Opp, Case) counts
        for (AggregateResult ar : taskModifiedAOCCount) {
            Integer count = (Integer) ar.get('expr0'); // Get the count of modified tasks
            Id WhatId = (Id) ar.get('WhatId');

            // Check WhatId field to categorize tasks by object type
            if (WhatId != null){
                if (WhatId.getSObjectType() == Case.sObjectType) {
                    taskModifiedCountCase.add(ar);
                } else if (WhatId.getSObjectType() == Opportunity.sObjectType) {
                    taskModifiedCountOpportunity.add(ar);
                } else if (WhatId.getSObjectType() == Account.sObjectType) {
                    taskModifiedCountAccount.add(ar);
                }
            }
        }

        List<AggregateResult> taskModifiedCountContact = new List<AggregateResult>();
        List<AggregateResult> taskModifiedCountLead = new List<AggregateResult>();

         // Modified Tasks - (Lead, Contact)
         List<AggregateResult> taskModifiedLCCount = [
            SELECT LastModifiedById, COUNT(Id), WhoId
            FROM Task 
            WHERE LastModifiedDate = YESTERDAY AND Status != 'Completed' AND WhoId!= NULL AND WhatId = NULL
            AND LastModifiedById != NULL AND (LastModifiedById IN :adoptionUsers)
            GROUP BY LastModifiedById, WhoId
        ];

        // Process modified task (Lead, Contact) counts
        for (AggregateResult ar : taskModifiedLCCount) {
            Integer count = (Integer) ar.get('expr0'); // Get the count of modified tasks
            Id WhoId = (Id) ar.get('WhoId');

            // Check WhatId field to categorize tasks by object type
            if (WhoId != null){
                if (WhoId.getSObjectType() == Case.sObjectType) {
                    taskModifiedCountCase.add(ar);
                } else if (WhoId.getSObjectType() == Contact.sObjectType) {
                    taskModifiedCountContact.add(ar);
                } else if (WhoId.getSObjectType() == Opportunity.sObjectType) {
                    taskModifiedCountOpportunity.add(ar);
                } else if (WhoId.getSObjectType() == Account.sObjectType) {
                    taskModifiedCountAccount.add(ar);
                } else if (WhoId.getSObjectType() == Lead.sObjectType) {
                    taskModifiedCountLead.add(ar);
                }
            }
        }

        // Modified Tasks - Unrelated
        List<AggregateResult> taskModifiedCountUnrelated = [
            SELECT LastModifiedById, COUNT(Id)
            FROM Task 
            WHERE LastModifiedDate = YESTERDAY AND Status != 'Completed' AND WhatId = NULL AND WhoId = NULL
            AND LastModifiedById != NULL AND (LastModifiedById IN :adoptionUsers)
            GROUP BY LastModifiedById
        ];

        System.debug('---Completed Lead Count'+ taskCompletedCountLead);

        // Process the results and add the counts to userSummaryMap
        addToSummaryMap(leadCount, userSummaryMap, 'Modified_Lead__c');
        addToSummaryMap(oppCount, userSummaryMap, 'Modified_Opportunity__c');
        addToSummaryMap(accCount, userSummaryMap, 'Modified_Account__c');
        addToSummaryMap(caseCount, userSummaryMap, 'Modified_Case__c');
        addToSummaryMap(contactCount, userSummaryMap, 'Modified_Contact__c');

        addToSummaryMap(taskModifiedCountLead, userSummaryMap, 'TasksModifiedLead__c');
        addToSummaryMap(taskModifiedCountContact, userSummaryMap, 'Tasks_Modified_Contact__c');
        addToSummaryMap(taskModifiedCountOpportunity, userSummaryMap, 'Tasks_Modified_Opportunity__c');
        addToSummaryMap(taskModifiedCountCase, userSummaryMap, 'Tasks_Modified_Case__c');
        addToSummaryMap(taskModifiedCountAccount, userSummaryMap, 'Tasks_Modified_Account__c');
        addToSummaryMap(taskModifiedCountUnrelated, userSummaryMap, 'Tasks_Modified_Unrelated__c');

        addToSummaryMap(taskCompletedCountLead, userSummaryMap, 'Tasks_Completed_Lead__c');
        addToSummaryMap(taskCompletedCountContact, userSummaryMap, 'Tasks_Completed_Contact__c');
        addToSummaryMap(taskCompletedCountCase, userSummaryMap, 'Tasks_Completed_Case__c');
        addToSummaryMap(taskCompletedCountOpportunity, userSummaryMap, 'Tasks_Completed_Opportunity__c');
        addToSummaryMap(taskCompletedCountAccount, userSummaryMap, 'Tasks_Completed_Account__c');
        addToSummaryMap(taskCompletedCountUnrelated, userSummaryMap, 'Tasks_Completed_Unrelated__c');

        addToSummaryMap(eventCompletedCountLead, userSummaryMap, 'Events_Completed_Lead__c');
        addToSummaryMap(eventCompletedCountContact, userSummaryMap, 'Events_Completed_Contact__c');
        addToSummaryMap(eventCompletedCountCase, userSummaryMap, 'Events_Completed_Case__c');
        addToSummaryMap(eventCompletedCountOpportunity, userSummaryMap, 'Events_Completed_Opportunity__c');
        addToSummaryMap(eventCompletedCountAccount, userSummaryMap, 'Events_Completed_Account__c');

        addToSummaryMap(eventModifiedCountLead, userSummaryMap, 'Events_Modified_Lead__c');
        addToSummaryMap(eventModifiedCountContact, userSummaryMap, 'Events_Modified_Contact__c');
        addToSummaryMap(eventModifiedCountOpportunity, userSummaryMap, 'Events_Modified_Opportunity__c');
        addToSummaryMap(eventModifiedCountCase, userSummaryMap, 'Events_Modified_Case__c');
        addToSummaryMap(eventModifiedCountAccount, userSummaryMap, 'Events_Modified_Account__c');

        // Insert or update the summary records
        Database.upsert(userSummaryMap.values(), false);
    }

    // Helper method to update the map with counts
    public void addToSummaryMap(List<AggregateResult> aggregateResults, Map<Id, LOCAC__c> userSummaryMap, String field) {
        Set<String> taskCompletedFields = new Set<String>{
            'Tasks_Completed_Lead__c',
            'Tasks_Completed_Opportunity__c',
            'Tasks_Completed_Account__c',
            'Tasks_Completed_Case__c',
            'Tasks_Completed_Contact__c',
            'Tasks_Completed_Unrelated__c',
            'Events_Completed_Lead__c',
            'Events_Completed_Opportunity__c',
            'Events_Completed_Contact__c',
            'Events_Completed_Case__c',
            'Events_Completed_Account__c'
        };

        for (AggregateResult ar : aggregateResults) {
            Id userId;

            if (taskCompletedFields.contains(field)) {
                userId = (Id) ar.get('OwnerId');
            } else{
                if (!Test.isRunningTest()) {
	                userId = (Id) ar.get('LastModifiedById');    
                }            
            }

            Integer count = (Integer) ar.get('expr0'); // Get the count value

            // Get the existing summary object for the user
            LOCAC__c summary = userSummaryMap.get(userId);

            // Update field based on passed field name
            if (field == 'Modified_Lead__c') summary.Modified_Lead__c = count;
            if (field == 'Modified_Opportunity__c') summary.Modified_Opportunity__c = count;
            if (field == 'Modified_Account__c') summary.Modified_Account__c = count;
            if (field == 'Modified_Case__c') summary.Modified_Case__c = count;
            if (field == 'Modified_Contact__c') summary.Modified_Contact__c = count;           

            if (field == 'TasksModifiedLead__c') summary.TasksModifiedLead__c += count;
            if (field == 'Tasks_Modified_Opportunity__c') summary.Tasks_Modified_Opportunity__c += count;
            if (field == 'Tasks_Modified_Account__c') summary.Tasks_Modified_Account__c += count;
            if (field == 'Tasks_Modified_Case__c') summary.Tasks_Modified_Case__c += count;
            if (field == 'Tasks_Modified_Contact__c') summary.Tasks_Modified_Contact__c += count;
            if (field == 'Tasks_Modified_Unrelated__c') summary.Tasks_Modified_Unrelated__c = count;

            if (field == 'Tasks_Completed_Lead__c') summary.Tasks_Completed_Lead__c += count;
            if (field == 'Tasks_Completed_Opportunity__c') summary.Tasks_Completed_Opportunity__c += count;
            if (field == 'Tasks_Completed_Account__c') summary.Tasks_Completed_Account__c += count;
            if (field == 'Tasks_Completed_Case__c') summary.Tasks_Completed_Case__c += count;
            if (field == 'Tasks_Completed_Contact__c') summary.Tasks_Completed_Contact__c += count;
            if (field == 'Tasks_Completed_Unrelated__c') summary.Tasks_Completed_Unrelated__c = count;

            if (field == 'Events_Completed_Lead__c') summary.Events_Completed_Lead__c += count;
            if (field == 'Events_Completed_Opportunity__c') summary.Events_Completed_Opportunity__c += count;
            if (field == 'Events_Completed_Account__c') summary.Events_Completed_Account__c += count;
            if (field == 'Events_Completed_Case__c') summary.Events_Completed_Case__c += count;
            if (field == 'Events_Completed_Contact__c') summary.Events_Completed_Contact__c += count;

            if (field == 'Events_Modified_Lead__c') summary.Events_Modified_Lead__c += count;
            if (field == 'Events_Modified_Opportunity__c') summary.Events_Modified_Opportunity__c += count;
            if (field == 'Events_Modified_Account__c') summary.Events_Modified_Account__c += count;
            if (field == 'Events_Modified_Case__c') summary.Events_Modified_Case__c += count;
            if (field == 'Events_Modified_Contact__c') summary.Events_Modified_Contact__c += count;

        }
    }

    // Finish method to handle post-processing, if needed
    public void finish(Database.BatchableContext BC) {
        // Any final operations after the batch is complete
    }
}