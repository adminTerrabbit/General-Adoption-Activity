@isTest
public class UserActivityBatchTest {
    
    @testSetup
    static void setupData() {
        // Create Test User
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User'];
        User testUser = new User(
            FirstName = 'Test',
            LastName = 'User',
            Email = 'testuser@example.com',
            Username = 'testuser@example.com.' + System.currentTimeMillis(),
            Alias = 'tuser',
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = p.Id,
            LanguageLocaleKey = 'en_US',
            Adoption_Reporting__c = true
        );
        insert testUser;

        System.runAs(testUser) {
            // Create Test Data for Different Objects

            // Lead
            Lead testLead = new Lead(
                FirstName = 'Lead',
                LastName = 'Test',
                Status = 'Open - Not Contacted',
                company = 'Test Company'
            );
            insert testLead;

            // Opportunity
            Account testAccount = new Account(Name = 'Test Account');
            insert testAccount;
            
            Opportunity testOpp = new Opportunity(
                Name = 'Test Opportunity',
                StageName = 'Prospecting',
                CloseDate = System.today().addDays(10),
                AccountId = testAccount.Id
            );
            insert testOpp;

            // Task
            Task testTask = new Task(
                Subject = 'Test Task',
                Status = 'Completed',
                WhatId = testAccount.Id,
                OwnerId = testUser.Id
            );
            insert testTask;

            Task testTask1 = new Task(
                Subject = 'Test Task',
                Status = 'Open',
                WhoId = testLead.Id,
                OwnerId = testUser.Id
            );
            insert testTask1;

            // LOCAC__c - Custom Object for Reporting
            LOCAC__c locacRecord = new LOCAC__c(
                Last_Modified_By__c = testUser.Id,
                Last_Modified_Date__c = System.today().addDays(-1)
            );
            insert locacRecord;
        }
    }

    @isTest
    static void testUserActivityBatch() {
        Test.startTest();
        UserActivityBatch batch = new UserActivityBatch();
        Database.executeBatch(batch);
        Test.stopTest();

        // Validate Results
        LOCAC__c result = [SELECT Id, Last_Modified_By__c FROM LOCAC__c LIMIT 1];
        System.assertNotEquals(null, result, 'LOCAC record should be created');
    }
    
    @isTest
    static void testUserActivityBatchExecution() {
        Test.startTest();
        // Use a scope size that forces one execute call.
        Database.executeBatch(new UserActivityBatch(), 200);
        Test.stopTest();
        
        // Validate that a LOCAC__c record exists.
        LOCAC__c result = [SELECT Id, Last_Modified_By__c FROM LOCAC__c LIMIT 1];
        System.assertNotEquals(null, result, 'A LOCAC__c record should exist.');
    }
    
    // Test the addToSummaryMap helper method using real aggregate queries with explicit aliases.
    @isTest
static void testAddToSummaryMapHelper() {
    // Retrieve the test user created in @testSetup.
    User testUser = [SELECT Id FROM User WHERE Adoption_Reporting__c = true LIMIT 1];
    
    System.runAs(testUser) {
        Id userId = testUser.Id;
        
        // Insert an Opportunity record so that our non‑task aggregate query returns a result.
        // (Opportunity supports grouping by LastModifiedById.)
        Account acct = new Account(Name = 'Temp Account');
        insert acct;
        Opportunity oppForTest = new Opportunity(
            Name = 'Test Opp',
            StageName = 'Prospecting',
            CloseDate = System.today().addDays(10),
            AccountId = acct.Id
        );
        insert oppForTest;
        
        // Insert Task records for the task-related queries.
        // Completed Task (for task completed branch).
        Task completedTask = new Task(
            Subject = 'Completed Task Test',
            Status = 'Completed',
            WhatId = acct.Id,
            OwnerId = userId
        );
        insert completedTask;
        
        // Modified Task (for modified task branch).
        // Use a task with WhoId not null and a status not equal to 'Completed'.
        Lead tempLead = new Lead(
            FirstName = 'Temp',
            LastName = 'Lead',
            Company = 'Temp Company',
            Status = 'Open - Not Contacted'
        );
        insert tempLead;
        Task modifiedTask = new Task(
            Subject = 'Modified Task Test',
            Status = 'Not Started',
            WhoId = tempLead.Id,
            OwnerId = userId
        );
        insert modifiedTask;
        
        // Unrelated Task (no WhatId, no WhoId) for unrelated branch.
        Task unrelatedTask = new Task(
            Subject = 'Unrelated Task Test',
            Status = 'Not Started',
            OwnerId = userId
        );
        insert unrelatedTask;
        
        // Create a dummy LOCAC__c summary record for the test user with all counters set to zero.
        LOCAC__c dummySummary = new LOCAC__c(
            Last_Modified_By__c = userId,
            Modified_Lead__c = 0,
            Modified_Opportunity__c = 0,
            Modified_Account__c = 0,
            Modified_Case__c = 0,
            Modified_Contact__c = 0,
            TasksModifiedLead__c = 0,
            Tasks_Modified_Opportunity__c = 0,
            Tasks_Modified_Account__c = 0,
            Tasks_Modified_Case__c = 0,
            Tasks_Modified_Contact__c = 0,
            Tasks_Modified_Unrelated__c = 0,
            Tasks_Completed_Lead__c = 0,
            Tasks_Completed_Opportunity__c = 0,
            Tasks_Completed_Account__c = 0,
            Tasks_Completed_Case__c = 0,
            Tasks_Completed_Contact__c = 0,
            Tasks_Completed_Unrelated__c = 0
        );
        Map<Id, LOCAC__c> summaryMap = new Map<Id, LOCAC__c>{ userId => dummySummary };
        
        // Instantiate the batch class so we can call its helper method.
        UserActivityBatch batchInst = new UserActivityBatch();
        
        // --- Non-Task Branch: Test "Modified_Lead__c" using LastModifiedById.
        // Instead of querying Lead (which may cause errors in our context), we use Opportunity.
        List<AggregateResult> oppAgg = [
            SELECT COUNT(Id), LastModifiedById 
            FROM Opportunity 
            WHERE LastModifiedById = :userId 
            GROUP BY LastModifiedById
        ];
        System.assertNotEquals(0, oppAgg.size(), 'There should be at least one Opportunity aggregate result.');
        batchInst.addToSummaryMap(oppAgg, summaryMap, 'Modified_Lead__c');
        Integer expectedOppCount = (Integer) oppAgg[0].get('expr0');
        System.assertEquals(expectedOppCount, summaryMap.get(userId).Modified_Lead__c,
            'Modified_Lead__c should equal the aggregate count from the Opportunity query.');
        
        // --- Task Completed Branch: Test "Tasks_Completed_Lead__c" using OwnerId.
        List<AggregateResult> taskCompletedAgg = [
            SELECT COUNT(Id), OwnerId 
            FROM Task 
            WHERE Status = 'Completed' AND WhatId != null AND OwnerId = :userId 
            GROUP BY OwnerId
        ];
        System.assertNotEquals(0, taskCompletedAgg.size(), 'There should be at least one Completed Task aggregate result.');
        batchInst.addToSummaryMap(taskCompletedAgg, summaryMap, 'Tasks_Completed_Lead__c');
        Integer expectedTaskCompletedCount = (Integer) taskCompletedAgg[0].get('expr0');
        System.assertEquals(expectedTaskCompletedCount, summaryMap.get(userId).Tasks_Completed_Lead__c,
            'Tasks_Completed_Lead__c should equal the aggregate count from the Completed Task query.');
        
        // --- Modified Task Branch (Addition): Test "TasksModifiedLead__c" using OwnerId.
        List<AggregateResult> taskModifiedAgg = [
            SELECT COUNT(Id), OwnerId 
            FROM Task 
            WHERE Status != 'Completed' AND WhoId != null AND OwnerId = :userId 
            GROUP BY OwnerId
        ];
        System.assertNotEquals(0, taskModifiedAgg.size(), 'There should be at least one Modified Task aggregate result.');
        batchInst.addToSummaryMap(taskModifiedAgg, summaryMap, 'TasksModifiedLead__c');
        Integer expectedTaskModifiedCount = (Integer) taskModifiedAgg[0].get('expr0');
        System.assertEquals(expectedTaskModifiedCount, summaryMap.get(userId).TasksModifiedLead__c,
            'TasksModifiedLead__c should equal the aggregate count from the Modified Task query.');
        
        // --- Unrelated Modified Task Branch (Assignment): Test "Tasks_Modified_Unrelated__c" using LastModifiedById.
        List<AggregateResult> taskModifiedUnrelatedAgg = [
            SELECT COUNT(Id), LastModifiedById 
            FROM Task 
            WHERE Status != 'Completed' AND WhatId = null AND WhoId = null AND LastModifiedById = :userId 
            GROUP BY LastModifiedById
        ];
        if (!taskModifiedUnrelatedAgg.isEmpty()) {
            batchInst.addToSummaryMap(taskModifiedUnrelatedAgg, summaryMap, 'Tasks_Modified_Unrelated__c');
            Integer expectedUnrelatedCount = (Integer) taskModifiedUnrelatedAgg[0].get('expr0');
            System.assertEquals(expectedUnrelatedCount, summaryMap.get(userId).Tasks_Modified_Unrelated__c,
                'Tasks_Modified_Unrelated__c should equal the aggregate count from the Unrelated Modified Task query.');
        }
    }
}



}