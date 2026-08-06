# D17 renamed this job to BreakDownGoalJob, but a queue outlives a rename:
# jobs enqueued by a pre-D17 deploy still carry the old class name and die at
# deserialization with UnknownJobClassError — before ApplicationJob's safety
# net can even see them. The alias lets them deserialize and run the
# replacement: same goal-first signature, and the breakdown guards itself
# against goals that were already planned. Delete once no pre-D17 queue could
# plausibly still hold work.
CategorizeGoalJob = BreakDownGoalJob
