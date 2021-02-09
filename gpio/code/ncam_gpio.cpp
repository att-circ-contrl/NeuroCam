// Attention Circuits Control Laboratory - GPIO device
// Main file.
// Written by Christopher Thomas.

//
// Includes

#include "ncam_gpio_includes.h"


//
// Functions


//
// Arduino entrypoints

void DoSetup()
{
  MCU_Init();

  ConfigPins(FOB_DEFAULT_PULLUPS);

  // Set up the timer before initializing the task, as task init reads
  // the clock.
  Timer_Init(CPU_SPEED, RTC_TICKS_PER_SECOND);

  ConfigureTask(FOB_DEFAULT_STROBE_PERIOD, FOB_DEFAULT_STROBE_HOLD);
  SetTaskActivity(TASK_AUTOSTART);

  // Add the timer callback _after_ initializing the task, as it calls the
  // task's update routine.
  Timer_RegisterCallback(&TimerCallback_ISR);

  InitHostLink();
}


int main(void)
{
  DoSetup();

  while (1)
  {
    PollHostInput();
    PollHostReporting();
  }

  return 0;
}


//
// This is the end of the file.
