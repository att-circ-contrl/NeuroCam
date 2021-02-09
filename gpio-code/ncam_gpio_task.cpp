// Attention Circuits Control Laboratory - GPIO device
// Project-specific task code (TTL fob).
// Written by Christopher Thomas.


//
// Includes

#include "ncam_gpio_includes.h"



//
// Private variables

volatile uint32_t last_strobe_time;
volatile bool strobe_state;

uint32_t strobe_period = FOB_DEFAULT_STROBE_PERIOD;
uint32_t strobe_duration = FOB_DEFAULT_STROBE_HOLD;

bool task_active = false;



//
// Functions


// Initializes task-specific state (task is left inactive).

void ConfigureTask(uint32_t new_period, uint32_t new_duration)
{
  last_strobe_time = Timer_Query();

  strobe_period = new_period;
  strobe_duration = new_duration;

  strobe_state = false;
  task_active = false;
}



// Queries the task configuration.

void QueryTaskParams(uint32_t &period, uint32_t &duration)
{
  period = strobe_period;
  duration = strobe_duration;
}



// Toggles the task on or off.

void SetTaskActivity(bool is_active)
{
  // Reinitialize if we're restarting.
  // Among other things, this resets event timing.
  if (is_active)
    ConfigureTask(strobe_period, strobe_duration);

  // Set the activity flag. (Configuring forced this to false.)
  task_active = is_active;
}



// Queries whether the task is active or inactive.

bool IsTaskActive(void)
{
  return task_active;
}



// Performs interrupt-driven updates to task state.

void PollTask_ISR()
{
  uint32_t this_time;

  if (task_active)
  {
    this_time = Timer_Query_ISR();

    if (strobe_state)
    {
      if (this_time > last_strobe_time + strobe_duration)
      {
        // Turn the light off.

        strobe_state = false;
        SetDIOBits(DIO_REG_OUTPUT, 0x00);
      }
    }
    else
    {
      if (this_time > last_strobe_time + strobe_period)
      {
        // Turn the light on, and reset the timeout.

        strobe_state = true;
        SetDIOBits(DIO_REG_OUTPUT, 0x01);

        last_strobe_time += strobe_period;
      }
    }
  }
}



//
// This is the end of the file.
