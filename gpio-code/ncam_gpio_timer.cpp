// Attention Circuits Control Laboratory - GPIO device
// Timer routines.
// Written by Christopher Thomas.


//
// Includes

#include "ncam_gpio_includes.h"


//
// Functions


// Timer interrupt callback.

void TimerCallback_ISR(void)
{
  // There's no need for pins to be queried or written via ISR.
  // Direct reads and writes are adequate.

  // Handle application-specific routines. This must be fast.
  PollTask_ISR();
}



//
// This is the end of the file.
