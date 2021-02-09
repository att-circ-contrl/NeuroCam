// Attention Circuits Control Laboratory - GPIO device
// Project-specific task code (TTL fob).
// Written by Christopher Thomas.


//
// Functions

// Initializes task-specific state (task is left inactive).
void ConfigureTask(uint32_t new_period, uint32_t new_duration);

// Queries task configuration.
void QueryTaskParams(uint32_t &period, uint32_t &duration);

// Toggles the task on or off.
void SetTaskActivity(bool is_active);

// Queries whether the task is active or inactive.
bool IsTaskActive(void);

// Performs interrupt-driven updates to task state.
void PollTask_ISR();


//
// This is the end of the file.
