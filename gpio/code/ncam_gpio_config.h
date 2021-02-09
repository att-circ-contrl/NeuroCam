// Attention Circuits Control Laboratory - GPIO device
// Configuration values and switches.
// Written by Christopher Thomas.

//
// Diagnostics constants

#define VERSION_STR "20161030"

#define DEVICETYPE "GPIOv1"
#define DEVICESUBTYPE "neurocam"

#define TASKNAME "light strobe"


//
// Task configuration constants

// Strobe timing.
// Period and hold time are in milliseconds.
#define FOB_DEFAULT_STROBE_PERIOD 5000
#define FOB_DEFAULT_STROBE_HOLD 20

// Indicates whether the strobe should be active on startup (bool).
#define TASK_AUTOSTART true


//
// Pin configuration constants

// Indicates whether input pins are pulled high. (bool value)
#define FOB_DEFAULT_PULLUPS true

// Input changes must be at least this many ticks apart to be recorded.
// FIXME - Debouncing NYI!
//define FOB_DIN_DEBOUNCE_TICKS 10


//
// Host link constants

// Host link baud rate.
// 115.2 can be done with high precision. 230.4 with coarser precision.
// 250.0 can be done with high precision but isn't supported by some terminals.
#define HOST_BAUD 115200
//define HOST_BAUD 230400

// Echo. (bool value)
#define ECHO_DEFAULT true

// Do we start reporting on power-up, or wait for it? (bool value)
#define REPORT_DEFAULT true

// Enable debugging commands.
#define DEBUG_ENABLE 1


//
// Timing constants

// CPU speed is the same for any of the AVR Arduino boards that we'd use.
// Make it a macro instead of an inline constant, just in case.
#define CPU_SPEED 16000000ul

// Number of RTC interrupts per second.
// This doesn't have to be human-readable. The host is responsible for
// timestamping, not us.
#define RTC_TICKS_PER_SECOND 1000ul


//
// This is the end of the file.
