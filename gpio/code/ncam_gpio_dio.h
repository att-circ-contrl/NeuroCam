// Attention Circuits Control Laboratory - GPIO device
// Digital I/O routines.
// Written by Christopher Thomas.


//
// Enums

enum reg_id_t
{
  DIO_REG_INPUT,
  DIO_REG_OUTPUT,
  DIO_REG_USER
};


//
// Functions

// Configures digital I/O pins.
void ConfigPins(bool want_pullups);

// Queries whether or not pull-ups are enabled.
bool QueryPinPullups(void);

// Queries the state of digital I/Os.
// NOTE - Physical inputs may change mid-stream. This is unavoidable.
uint32_t GetDIOBits(reg_id_t target);

// Sets the state of output bits.
// Returns the resulting state.
uint32_t SetDIOBits(reg_id_t target, uint32_t value);

// Returns the number of digital I/O pins of a given class.
int GetDIOCount(reg_id_t target);

// FIXME - User-configurable registers need a config function here.


//
// This is the end of the file.
