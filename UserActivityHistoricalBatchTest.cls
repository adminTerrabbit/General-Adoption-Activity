@isTest
private class UserActivityHistoricalBatchTest {

    // Helper method to create a test user with Adoption_Reporting__c = true.
    private static User createTestUser() {
        // Query an existing profile to assign to our test user.
        Profile p = [SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1];
        User testUser = new User(
            Alias = 'tuser',
            Email = 'testuser@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Testing',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'testuser' + DateTime.now().getTime() + '@example.com',
            Adoption_Reporting__c = true  // custom checkbox field
        );
        insert testUser;
        return testUser;
    }

    @isTest
    static void testUserActivityHistoricalBatch() {
        // Create a test adoption user.
        User testUser = createTestUser();

        // Create a test account (required for Contact).
        Account acct = new Account(Name='Test Account');
        insert acct;

        // Run all DML as the test user so that system fields (like LastModifiedDate) are set as expected.
        System.runAs(testUser) {
            // Create one Lead.
            Lead leadRec = new Lead(LastName = 'Lead', Company = 'Test Company');
            insert leadRec;
            
            // Create one Opportunity.
            Opportunity oppRec = new Opportunity(
                Name = 'Opportunity', 
                StageName = 'Prospecting', 
                CloseDate = Date.today().addDays(10)
            );
            insert oppRec;
            
            // Create one Account.
            Account accRec = new Account(Name = 'Account');
            insert accRec;
            
            // Create one Case.
            Case caseRec = new Case(Subject = 'Test Case', Origin = 'Phone');
            insert caseRec;
            
            // Create one Contact.
            Contact conRec = new Contact(LastName = 'Contact', AccountId = acct.Id);
            insert conRec;
            
            // Insert Tasks that will be aggregated.
            // Task Completed using WhatId (for Case)
            Task taskCompletedAOC = new Task(
                Subject = 'Completed Task AOC',
                Status = 'Not Completed', // initially not completed
                WhatId = caseRec.Id,
                OwnerId = testUser.Id
            );
            insert taskCompletedAOC;
            // Now update to mark as completed (system will auto-populate CompletedDateTime)
            taskCompletedAOC.Status = 'Completed';
            update taskCompletedAOC;
            
            // Task Completed using WhoId (for Lead)
            Task taskCompletedLC = new Task(
                Subject = 'Completed Task LC',
                Status = 'Not Completed', // initially not completed
                WhoId = leadRec.Id,
                OwnerId = testUser.Id
            );
            insert taskCompletedLC;
            // Update to mark as completed
            taskCompletedLC.Status = 'Completed';
            update taskCompletedLC;
            
            // Task Modified using WhatId (for Opportunity)
            Task taskModifiedAOC = new Task(
                Subject = 'Modified Task AOC',
                Status = 'Not Completed',
                WhatId = oppRec.Id,
                OwnerId = testUser.Id
            );
            insert taskModifiedAOC;
            
            // Task Modified using WhoId (for Contact)
            Task taskModifiedLC = new Task(
                Subject = 'Modified Task LC',
                Status = 'Not Completed',
                WhoId = conRec.Id,
                OwnerId = testUser.Id
            );
            insert taskModifiedLC;
        }
        
        // Execute the batch.
        Test.startTest();
        UserActivityHistoricalBatch batchJob = new UserActivityHistoricalBatch();
        // We use a small batch size since our test data is minimal.
        Database.executeBatch(batchJob, 200);
        Test.stopTest();
        
        // Query the LOCAC__c records created for the test user for today's date.
        // (Our batch creates one summary record per user per day in the range.
        // We look for the one with Last_Modified_Date__c equal to today.)
        List<LOCAC__c> summaries = [
            SELECT Last_Modified_By__c,
                   Last_Modified_Date__c,
                   Modified_Lead__c,
                   Modified_Opportunity__c,
                   Modified_Account__c,
                   Modified_Case__c,
                   Modified_Contact__c,
                   TasksModifiedLead__c,
                   Tasks_Modified_Opportunity__c,
                   Tasks_Modified_Account__c,
                   Tasks_Modified_Case__c,
                   Tasks_Modified_Contact__c,
                   Tasks_Completed_Lead__c,
                   Tasks_Completed_Opportunity__c,
                   Tasks_Completed_Account__c,
                   Tasks_Completed_Case__c,
                   Tasks_Completed_Contact__c
            FROM LOCAC__c
            WHERE Last_Modified_By__c = :testUser.Id
              AND Last_Modified_Date__c = :Date.today()
        ];
        
        // At least one summary record for today should have been created.
        System.assertNotEquals(0, summaries.size(), 'A summary record for today should be created.');
        
        // Since our test inserted one record per object (and one task per scenario),
        // we expect the following non-zero counts for today's summary record:
        // Modified Leads: 1
        // Modified Opportunities: 1
        // Modified Accounts: 1
        // Modified Cases: 1
        // Modified Contacts: 1
        // Tasks_Completed_Case__c: 1 (from whatId completed task)
        // Tasks_Completed_Lead__c: 1 (from whoId completed task)
        // Tasks_Modified_Opportunity__c: 1 (from whatId modified task)
        // Tasks_Modified_Contact__c: 1 (from whoId modified task)
        // The other task fields remain 0.
        LOCAC__c todaySummary;
        for (LOCAC__c rec : summaries) {
            todaySummary = rec;
            break;
        }
        
        System.assertEquals(1, todaySummary.Modified_Lead__c, 'Lead modified count should be 1.');
        System.assertEquals(1, todaySummary.Modified_Opportunity__c, 'Opportunity modified count should be 1.');
        System.assertEquals(1, todaySummary.Modified_Account__c, 'Account modified count should be 1.');
        System.assertEquals(1, todaySummary.Modified_Case__c, 'Case modified count should be 1.');
        System.assertEquals(1, todaySummary.Modified_Contact__c, 'Contact modified count should be 1.');
        
        System.assertEquals(0, todaySummary.TasksModifiedLead__c, 'TasksModifiedLead should be 0 as no task for lead modified using WhoId was inserted.');
        System.assertEquals(2, todaySummary.Tasks_Modified_Opportunity__c, 'Modified Opportunity task count should be 2.');
        System.assertEquals(0, todaySummary.Tasks_Modified_Account__c, 'Modified Account task count should be 0.');
        System.assertEquals(0, todaySummary.Tasks_Modified_Case__c, 'Modified Case task count should be 0.');
        System.assertEquals(1, todaySummary.Tasks_Modified_Contact__c, 'Modified Contact task count should be 1.');
        
        System.assertEquals(1, todaySummary.Tasks_Completed_Lead__c, 'Completed Lead task count should be 1.');
        System.assertEquals(0, todaySummary.Tasks_Completed_Opportunity__c, 'Completed Opportunity task count should be 0.');
        System.assertEquals(0, todaySummary.Tasks_Completed_Account__c, 'Completed Account task count should be 0.');
        System.assertEquals(1, todaySummary.Tasks_Completed_Case__c, 'Completed Case task count should be 1.');
        System.assertEquals(0, todaySummary.Tasks_Completed_Contact__c, 'Completed Contact task count should be 0.');
    }
}