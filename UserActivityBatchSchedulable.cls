global class UserActivityBatchSchedulable implements Schedulable {
	global void execute(SchedulableContext sc) {
        // Schedule the batch job to run
        UserActivityBatch BatchJob = new UserActivityBatch();
		Database.executeBatch(BatchJob, 100);
    }
}