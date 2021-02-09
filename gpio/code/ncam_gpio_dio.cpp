// Attention Circuits Control Laboratory - GPIO device
// Digital I/O routines.
// Written by Christopher Thomas.


//
// Includes

#include "ncam_gpio_includes.h"



//
// Private macros

// Input and output masks for various ports.

// FIXME - We have 18 uncontested pins available, and only use 9.

// NOTE - Don't touch B6/7 (crystal) or D0/1 (UART).
// These should be protected by pin function logic, but be careful anyways.

// We have one output line on B5 (digital line 13).
// Inputs are D5..D7 (digital 5..7) and B0..B4 (digital 8..12).

#define PORTB_INPUT_MASK  0b00011111
#define PORTB_OUTPUT_MASK 0b00100000
#define PORTC_INPUT_MASK  0x00
#define PORTC_OUTPUT_MASK 0x00
#define PORTD_INPUT_MASK  0b11100000
#define PORTD_OUTPUT_MASK 0b00000000



//
// Private variables


bool using_pullups = false;



//
// Functions


// Configures digital I/O pins.

void ConfigPins(bool want_pullups)
{
  // Pins are initialized to high-Z inputs at mcu start.

  // Configure outputs.
  DDRB = PORTB_OUTPUT_MASK;
  DDRC = PORTC_OUTPUT_MASK;
  DDRD = PORTD_OUTPUT_MASK;

  // Configure pull-ups if we have those.
  if (want_pullups)
  {
    PORTB = PORTB_INPUT_MASK;
    PORTC = PORTC_INPUT_MASK;
    PORTD = PORTD_INPUT_MASK;
  }

  using_pullups = want_pullups;
}



// Queries whether or not pull-ups are enabled.

bool QueryPinPullups(void)
{
  return using_pullups;
}



// Queries the current state of digital I/Os.
// NOTE - Physical inputs may change mid-stream. This is unavoidable.

uint32_t GetDIOBits(reg_id_t target)
{
  uint32_t result;
  uint8_t portbval, portdval, scratch;

  result = 0x00;

  // Read the pin values.
  portbval = PINB;
  portdval = PIND;

  // Shift and mask to get the desired virtual register's contents.

  switch (target)
  {
    case DIO_REG_INPUT:
      portbval &= PORTB_INPUT_MASK;
      portdval &= PORTD_INPUT_MASK;
      scratch = (portbval << 3) | (portdval >> 5);
      result = scratch;
      break;

    case DIO_REG_OUTPUT:
      portbval &= PORTB_OUTPUT_MASK;
      scratch = (portbval >> 5);
      result = scratch;
      break;

    case DIO_REG_USER:
      // No user-configurable bits.
      break;

    default:
      // Bogus target.
      break;
  }

  return result;
}



// Sets the state of output bits.
// Returns the resulting state.

uint32_t SetDIOBits(reg_id_t target, uint32_t value)
{
  uint8_t portbval, scratch;

  switch (target)
  {
    case DIO_REG_OUTPUT:
      // FIXME - Cheat. There's only one output pin.
      portbval = 0x00;
      if (0 != value)
        portbval = PORTB_OUTPUT_MASK;

      // Set the port values.
      // Remember that input pull-ups need to be set too.

      if (using_pullups)
        portbval |= PORTB_INPUT_MASK;

      PORTB = portbval;

      break;

    case DIO_REG_USER:
      // No user-configurable bits.
      break;

    default:
      // Bogus target (can't write to an input).
      break;
  }

  // Reread, to get the result.
  return GetDIOBits(target);
}



// Returns the number of digital I/O pins of a given class.

int GetDIOCount(reg_id_t target)
{
  int result;

  result = 0;

  // FIXME - Just hardwire this.
  switch (target)
  {
    case DIO_REG_INPUT:
      result = 8;
      break;

    case DIO_REG_OUTPUT:
      result = 1;
      break;

    case DIO_REG_USER:
      result = 0;
      break;

    default:
      // Bogus target.
      break;
  }

  return result;
}



//
// This is the end of the file.
