**Board task cards drop their section chips**: The Later/Today/Done cards on
the Tasks board no longer render section tags — `tasks/_card` passes
`sections: false` to `shared/item_chips`, the same flag goal cards already use.
Due date, goal chip, and the "from <name>" attribution on a household member's
task all stay. Chips remain everywhere else a task is rendered (the `tasks/_task`
row, the task show page), where the surrounding view isn't already the Tasks
lens.
