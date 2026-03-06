@isTest
private class UserActivityBatchSchedulableTest {
    
    @isTest static void testSchedulableExecution() {
        // Create test data for the batch job to process.
        // Replace Account with the appropriate object if needed.
        Account testAcc = new Account(Name = 'Test Account');
        insert testAcc;
        
        // Compute a Datetime one minute in the future.
        Datetime futureTime = System.now().addMinutes(1);
        
        // Build a valid CRON expression:
        // Format: Seconds Minutes Hours Day_of_month Month Day_of_week Year
        // Use '?' for the day-of-week.
        String cronExp = String.valueOf(futureTime.second()) + ' ' +
                         String.valueOf(futureTime.minute()) + ' ' +
                         String.valueOf(futureTime.hour()) + ' ' +
                         String.valueOf(futureTime.day()) + ' ' +
                         String.valueOf(futureTime.month()) + ' ? ' +
                         String.valueOf(futureTime.year());
        
        Test.startTest();
        // Schedule the Schedulable class.
        System.schedule('Test_UserActivityBatchSchedulable', cronExp, new UserActivityBatchSchedulable());
        Test.stopTest();
        
        // Query for the batch job record that was enqueued by the schedulable.
        List<AsyncApexJob> batchJobs = [SELECT Id, Status, JobType 
                                        FROM AsyncApexJob 
                                        WHERE JobType = 'BatchApex'
                                        ORDER BY CreatedDate DESC 
                                        LIMIT 1];
        
        System.assert(!batchJobs.isEmpty(), 'No Batch Apex job record was found.');
        System.assertEquals('Queued', batchJobs[0].Status, 'The batch job did not complete as expected.');
    }
}