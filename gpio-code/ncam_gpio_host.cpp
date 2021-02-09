// Attention Circuits Control Laboratory - GPIO device
// Host communication.
// Written by Christopher Thomas.


//
// Includes

#include "ncam_gpio_includes.h"



//
// Private macros

// Maximum length of an actual command word (opcode).
#define MAX_OPCODE_CHARS 3

// Length of the output scratch string used with snprintf().
#define SCRATCH_STRING_SIZE 20



//
// Private enums

enum parse_result_t
{
  PARSER_EMPTY,
  PARSER_VALID,
  PARSER_BAD
};

enum parse_state_t
{
  STATE_PREAMBLE,
  STATE_OPCODE,
  STATE_GAP,
  STATE_ARGUMENT,
  STATE_TAIL,
  STATE_ERROR
};



//
// Private variables

// Echo state.
bool echo_active;

// Flag indicating that we want to see the next sample, changed or not.
bool force_output;
// Flag indicating that we do want to automatically report changes.
bool report_changes;


// Command buffer.

// Unparsed command.
// This is either NULL or guaranteed NULL-terminated.
char *rawcommand;

// Parsed command.
char opcode[MAX_OPCODE_CHARS];
bool argvalid;
uint32_t argument;



//
// Private prototypes


// Initializes reporting state.
void InitReporting(bool want_reports);

// Initializes command-parsing input.
void InitRawCommand();

// Initializes command-parsing output.
void InitOpCommand();

// Checks to see if the contents of the command buffer are valid.
parse_result_t ValidateCommand();

// Prints a short "unrecognized command" message.
void PrintShortHelp();

// Prints a full help screen.
void PrintLongHelp();

// Prints a description of system state.
void PrintFullQuery();

// Handles the most recently parsed command.
void HandleCommand();

// Prints a formatted hex value with zero-padding and appropriate width.
// We could do this via UART_PrintHex..(), except for the 24-bit case.
void PrintHexValue(uint32_t value, int bits);

// Dumps full config register state to the serial port (debug command).
void DebugDumpRegState();



//
// Functions



// Initializes reporting state.

void InitReporting(bool want_reports)
{
  force_output = false;
  report_changes = false;

  if (want_reports)
  {
    // This always has to be true when report_changes is toggled on,
    // as it tells the reporter to initialize cached values.
    force_output = true;
    report_changes = true;
  }
}



// Initializes communications with the host.

void InitHostLink()
{
  InitRawCommand();

  echo_active = ECHO_DEFAULT;

  InitReporting(REPORT_DEFAULT);

  UART_Init(CPU_SPEED, HOST_BAUD);
}



// Initializes command-parsing input.

void InitRawCommand()
{
  rawcommand = NULL;
}



// Initializes command-parsing output.

void InitOpCommand()
{
  int idx;

  for (idx = 0; idx < MAX_OPCODE_CHARS; idx++)
    opcode[idx] = 0;

  argvalid = false;
  argument = 0;
}



// Checks to see if the contents of the command buffer are valid.

parse_result_t ValidateCommand()
{
  parse_result_t result;
  parse_state_t state;
  int rawidx, opidx;
  char thischar;
  bool special_case_help;

  result = PARSER_EMPTY;


  // Scan the command string, testing against "^\s*\w+\s+(\d+)?\s*$",
  // more or less. The opcode can be up to three letters, nothing else.

  InitOpCommand();
  state = STATE_PREAMBLE;
  opidx = 0;
  special_case_help = false;
  thischar = 0;

  for (rawidx = 0;
    0 != (thischar = rawcommand[rawidx]);
    rawidx++)
  {
    // First pass: update the state based on what we're looking at.
    switch (state)
    {
      case STATE_PREAMBLE:
        if ( (('A' <= thischar) && ('Z' >= thischar))
          || (('a' <= thischar) && ('z' >= thischar)) )
          state = STATE_OPCODE;
        else if (' ' < thischar)
        {
          state = STATE_ERROR;

          if ('?' == thischar)
            special_case_help = true;
        }
        break;

      case STATE_OPCODE:
        if ( (('A' <= thischar) && ('Z' >= thischar))
          || (('a' <= thischar) && ('z' >= thischar)) )
          // Keep the same state.
          state = STATE_OPCODE;
        else if (' ' >= thischar)
          state = STATE_GAP;
        else
          state = STATE_ERROR;
        break;

      case STATE_GAP:
        if (('0' <= thischar) && ('9' >= thischar))
          state = STATE_ARGUMENT;
        else if (' ' < thischar)
          state = STATE_ERROR;
        break;

      case STATE_ARGUMENT:
        if (('0' <= thischar) && ('9' >= thischar))
          // Keep the same state.
          state = STATE_ARGUMENT;
        else if (' ' >= thischar)
          state = STATE_TAIL;
        else
          state = STATE_ERROR;
        break;

      case STATE_TAIL:
        if (' ' < thischar)
          state = STATE_ERROR;
        break;

      default:
        // Error state; nothing more to do.
        break;
    }

    // Second pass: We know what we're looking at. Update it.
    switch (state)
    {
      case STATE_OPCODE:
        // Convert lower case to upper case.
        if (('a' <= thischar) && ('z' >= thischar))
        {
          thischar -= 'a';
          thischar += 'A';
        }
        // Add this character, if there's room for it.
        if (opidx < MAX_OPCODE_CHARS)
        {
          opcode[opidx] = thischar;
          opidx++;
        }
        else
          state = STATE_ERROR;
        break;

      case STATE_ARGUMENT:
        argvalid = true;
        argument *= 10;
        thischar -= '0';
        argument += (uint32_t) thischar;
        break;

      default:
        // Whatever this is, there's no further processing to do.
        break;
    }

    // Finished handling this character.
  }

  // Third pass: Special-case "?", turning it into "HLP".
  // This will have been rejected due to non-alphabetical opcode characters.
  if (special_case_help)
  {
    // Squash any processing we've done.
    InitOpCommand();

    // Manually stuff the buffer, pretending we got "HLP" and then "<cr>".
    opidx = 3;
    opcode[0] = 'H';
    opcode[1] = 'L';
    opcode[2] = 'P';

    state = STATE_OPCODE;
  }

  // Fourth pass: Make sure we had _exactly_ MAX_OPCODE_CHARS in the
  // opcode, if we had anything at all.
  if ( (STATE_PREAMBLE != state) && (opidx != MAX_OPCODE_CHARS) )
    state = STATE_ERROR;


  // Figure out whether we had something valid or not.

  if (STATE_ERROR == state)
  {
    InitOpCommand();
    result = PARSER_BAD;
  }
  else if (STATE_PREAMBLE == state)
    result = PARSER_EMPTY;
  else
    result = PARSER_VALID;


  // Done.
  return result;
}



// Prints a short "unrecognized command" message.

void PrintShortHelp()
{
  int idx;
  char thischar;

  UART_QueueSend_P(PSTR("Unrecognized command:  \""));

  // Take this apart character by character, in case there are unprintable
  // characters in the string.
  for (idx = 0;
    0 != (thischar = rawcommand[idx]);
    idx++)
  {
    if ((32 <= thischar) && (126 >= thischar))
    {
      UART_PrintChar(thischar);
    }
    else
    {
      UART_PrintChar('<');
      PrintHexValue(thischar, 8);
      UART_PrintChar('>');
    }
  }

  UART_QueueSend_P(PSTR("\". Type \"?\" or \"HLP\" for help.\r\n"));
}



// Prints a full help screen.

void PrintLongHelp()
{
  UART_QueueSend_P(PSTR(
"Commands:\r\n"
" ?, HLP  :  Help screen.\r\n"
"    IDQ  :  Device identity query.\r\n"
"    QRY  :  Query system state.\r\n"
"    INI  :  Reinitialize (clock and event reset, pins to default config).\r\n"
"  ECH 1/0:  Start/stop echoing typed characters back to the host.\r\n"
"    WRO n:  Set the output bank to data value n.\r\n"
"    WRU n:  Set the user-configurable bank outputs to data value n.\r\n"
"    RDI  :  Read the state of the input bank.\r\n"
"    RDO  :  Read the state of the output bank.\r\n"
"    RDU  :  Read the state of the user-configurable bank.\r\n"
"  REP 1/0:  Start/stop automatically reporting changes in I/O lines.\r\n"
"  PPU 1/0:  Enable/disable input pin pull-up resistors.\r\n"
"  TSK 1/0:  Start/stop the device's preconfigured task.\r\n"
"    TPP n:  (task) Set pulse period to n ticks.\r\n"
"    TPD n:  (task) Set pulse duration to n ticks.\r\n"
  ));
#if DEBUG_ENABLE
  UART_QueueSend_P(PSTR(
"    DDC  :  (debug) Dump MCU configuration register contents.\r\n"
  ));
#endif
}



// Prints a description of system state.

void PrintFullQuery()
{
  uint32_t dval_input, dval_output, dval_user;
  uint32_t thistime;
  uint32_t strobe_period, strobe_duration;

  // Read the current I/O line values.
  // This doesn't need locking.
  dval_input = GetDIOBits(DIO_REG_INPUT);
  dval_output = GetDIOBits(DIO_REG_OUTPUT);
  dval_user = GetDIOBits(DIO_REG_USER);

  // Get the timestamp.
  // This makes its own locking call.
  thistime = Timer_Query();


  // Banner.
  UART_QueueSend_P(
    PSTR("System state (all values in base 10 unless noted):\r\n"));

  // Device and version information.
  UART_QueueSend_P(PSTR("  Device type:  "));
  UART_QueueSend_P(PSTR(DEVICETYPE));
  UART_QueueSend_P(PSTR("    Subtype/Configuration:  "));
  UART_QueueSend_P(PSTR(DEVICESUBTYPE));
  UART_QueueSend_P(PSTR("\r\n  Preconfigured task:  "));
  UART_QueueSend_P(PSTR(TASKNAME));
  UART_QueueSend_P(PSTR("\r\n  Firmware version:  "));
  UART_QueueSend_P(PSTR(VERSION_STR));
  UART_QueueSend_P(PSTR("\r\n  Debugging commands:  "));
  UART_QueueSend_P(DEBUG_ENABLE ? PSTR("enabled") : PSTR("disabled"));
  UART_QueueSend_P(PSTR("\r\n"));

  // RTC information.
  UART_QueueSend_P(PSTR("  Timestamp:  "));
  UART_PrintUInt(thistime);
  UART_QueueSend_P(PSTR(" ticks\r\n"));
  UART_QueueSend_P(PSTR("  Clock ticks per second:  "));
  UART_PrintUInt(RTC_TICKS_PER_SECOND);
  UART_QueueSend_P(PSTR("\r\n"));

  // Digital I/O state.
  UART_QueueSend_P(PSTR("  Digital I/Os (Input/Output/User-config):  "));
  UART_PrintUInt(GetDIOCount(DIO_REG_INPUT));
  UART_QueueSend_P(PSTR(" / "));
  UART_PrintUInt(GetDIOCount(DIO_REG_OUTPUT));
  UART_QueueSend_P(PSTR(" / "));
  UART_PrintUInt(GetDIOCount(DIO_REG_USER));
  UART_QueueSend_P(PSTR("\r\n  Input pull-up resistors?  "));
  UART_QueueSend_P(QueryPinPullups() ? PSTR("yes") : PSTR("no"));
  UART_QueueSend_P(PSTR("\r\n     Input state (hex):  "));
  PrintHexValue(dval_input, GetDIOCount(DIO_REG_INPUT));
  UART_QueueSend_P(PSTR("\r\n    Output state (hex):  "));
  PrintHexValue(dval_output, GetDIOCount(DIO_REG_OUTPUT));
  UART_QueueSend_P(PSTR("\r\n      User state (hex):  "));
  PrintHexValue(dval_user, GetDIOCount(DIO_REG_USER));
  UART_QueueSend_P(PSTR("\r\n"));
  // FIXME - Configuration of user-configurable registers goes here!

  // Task-specific state.

  strobe_period = 0;
  strobe_duration = 0;
  QueryTaskParams(strobe_period, strobe_duration);

  UART_QueueSend_P(PSTR("  Task-specific state:\r\n"));
  UART_QueueSend_P(PSTR("    Enabled?  "));
  UART_QueueSend_P(IsTaskActive() ? PSTR("yes") : PSTR("no"));
  UART_QueueSend_P(PSTR("\r\n    Synch light period (ticks):  "));
  UART_PrintUInt(strobe_period);
  UART_QueueSend_P(PSTR("\r\n    Synch light duration (ticks):  "));
  UART_PrintUInt(strobe_duration);
  UART_QueueSend_P(PSTR("\r\n"));

  // Banner.
  UART_QueueSend_P(PSTR("End of system state.\r\n"));
}



// Handles the most recently parsed command.

void HandleCommand()
{
  bool command_valid;
  uint32_t scratchval;
  int scratchcount;
  char scratchchar;
  uint32_t old_period, old_duration;
  bool old_activity;

  // Whatever we have, it's passed parsing.
  // Examine the opcode and argument and try to process them.

  command_valid = true;

  if (('H' == opcode[0]) && ('L' == opcode[1]) && ('P' == opcode[2])
    && (!argvalid))
  {
    PrintLongHelp();
  }
  else if (('I' == opcode[0]) && ('D' == opcode[1]) && ('Q' == opcode[2])
    && (!argvalid))
  {
    // Device type identifier, plus auxiliary data.
    UART_QueueSend_P(PSTR("devicetype: "));
    UART_QueueSend_P(PSTR(DEVICETYPE));
    UART_QueueSend_P(PSTR("  subtype: "));
    UART_QueueSend_P(PSTR(DEVICESUBTYPE));
    UART_QueueSend_P(PSTR("  task: "));
    UART_QueueSend_P(PSTR(TASKNAME));
    UART_QueueSend_P(PSTR("\r\n"));
  }
  else if (('Q' == opcode[0]) && ('R' == opcode[1]) && ('Y' == opcode[2])
    && (!argvalid))
  {
    PrintFullQuery();
  }
  else if (('I' == opcode[0]) && ('N' == opcode[1]) && ('I' == opcode[2])
    && (!argvalid))
  {
    // Reinit state.
    // None of this needs locking.

    ConfigPins(FOB_DEFAULT_PULLUPS);

    Timer_Reset();
    ConfigureTask(FOB_DEFAULT_STROBE_PERIOD, FOB_DEFAULT_STROBE_HOLD);
    SetTaskActivity(TASK_AUTOSTART);

    InitReporting(REPORT_DEFAULT);
  }
  else if (('E' == opcode[0]) && ('C' == opcode[1]) && ('H' == opcode[2])
    && argvalid)
  {
    if (0 == argument)
      echo_active = false;
    else if (1 == argument)
      echo_active = true;
    else
      command_valid = false;
  }
  else if (('R' == opcode[0]) && ('E' == opcode[1]) && ('P' == opcode[2])
    && argvalid)
  {
    if (0 == argument)
      InitReporting(false);
    else if (1 == argument)
      InitReporting(true);
    else
      command_valid = false;
  }
  else if (('W' == opcode[0]) && ('R' == opcode[1]) && argvalid)
  {
    // This doesn't need locking.
    if ('O' == opcode[2])
      SetDIOBits(DIO_REG_OUTPUT, argument);
    else if ('U' == opcode[2])
      SetDIOBits(DIO_REG_USER, argument);
    else
      command_valid = false;
  }
  else if (('R' == opcode[0]) && ('D' == opcode[1]) && (!argvalid))
  {
    scratchval = 0xdeadbeef;
    scratchcount = 32;
    scratchchar = 'X';

    // This doesn't need locking.
    if ('I' == opcode[2])
    {
      scratchval = GetDIOBits(DIO_REG_INPUT);
      scratchcount = GetDIOCount(DIO_REG_INPUT);
      scratchchar = 'I';
    }
    else if ('O' == opcode[2])
    {
      scratchval = GetDIOBits(DIO_REG_OUTPUT);
      scratchcount = GetDIOCount(DIO_REG_OUTPUT);
      scratchchar = 'O';
    }
    else if ('U' == opcode[2])
    {
      scratchval = GetDIOBits(DIO_REG_USER);
      scratchcount = GetDIOCount(DIO_REG_USER);
      scratchchar = 'U';
    }
    else
      command_valid = false;

    if (command_valid)
    {
      UART_PrintChar(scratchchar);
      UART_QueueSend_P(PSTR(": "));
      PrintHexValue(scratchval, scratchcount);
      UART_QueueSend_P(PSTR("\r\n"));
    }
  }
  else if (('P' == opcode[0]) && ('P' == opcode[1]) && ('U' == opcode[2])
    && argvalid)
  {
    if (0 == argument)
      ConfigPins(false);
    else if (1 == argument)
      ConfigPins(true);
    else
      command_valid = false;
  }
  else if (('T' == opcode[0]) && ('S' == opcode[1]) && ('K' == opcode[2])
    && argvalid)
  {
    if (0 == argument)
      SetTaskActivity(false);
    else if (1 == argument)
      SetTaskActivity(true);
    else
      command_valid = false;
  }
  else if (('T' == opcode[0]) && ('P' == opcode[1]) && ('P' == opcode[2])
    && argvalid)
  {
    // Get current parameters.
    old_activity = IsTaskActive();
    old_period = 0;
    old_duration = 0;
    QueryTaskParams(old_period, old_duration);

    // Set new parameters.
    ConfigureTask(argument, old_duration);

    // FIXME - Keeping the task active if it was active before!
    SetTaskActivity(old_activity);
  }
  else if (('T' == opcode[0]) && ('P' == opcode[1]) && ('D' == opcode[2])
    && argvalid)
  {
    // Get current parameters.
    old_activity = IsTaskActive();
    old_period = 0;
    old_duration = 0;
    QueryTaskParams(old_period, old_duration);

    // Set new parameters.
    ConfigureTask(old_period, argument);

    // FIXME - Keeping the task active if it was active before!
    SetTaskActivity(old_activity);
  }
#if DEBUG_ENABLE
  else if (('D' == opcode[0]) && ('D' == opcode[1]) && ('C' == opcode[2])
    && (!argvalid))
  {
    // FIXME - Debugging.
    DebugDumpRegState();
  }
#endif
  else
    command_valid = false;

  if (!command_valid)
    PrintShortHelp();
}



// Polling entry point for handling text from the host.

void PollHostInput()
{
  int rawserial;
  char thischar;
  parse_result_t validity;
  int charcount;

  // As long as the serial port has been initialized, this returns a valid
  // result (which may be a NULL pointer).
  rawcommand = UART_GetNextLine();

  if (NULL != rawcommand)
  {
    // We have a new line of input. Attempt to process it.

    // Echo, if we've been asked to.
    // Remember that it's been stripped of any newlines.
    if (echo_active)
    {
      UART_QueueSend(rawcommand);
      UART_QueueSend_P(PSTR("\r\n"));
    }

    // See if we can parse this.
    validity = ValidateCommand();

    // If this looks legit, act on it. Otherwise report it.
    // NOTE - The raw command is still in the buffer, so that we can
    // still report errors from HandleCommand().
    if (PARSER_VALID == validity)
      HandleCommand();
    else if (PARSER_BAD == validity)
      PrintShortHelp();

    // Release this line from the buffer.
    UART_DoneWithLine();

    // Reset the command state.
    InitRawCommand();
  }
}



// Prints a formatted hex value with zero-padding and appropriate width.
// We could do this via UART_PrintHex..(), except for the 24-bit case.

void PrintHexValue(uint32_t value, int bits)
{
  static char scratchstr[SCRATCH_STRING_SIZE + 1];

  // Make sure we aren't still using the scratch string.
  UART_WaitForSendDone();

  // Format this data.
  if (8 >= bits)
    snprintf(scratchstr, SCRATCH_STRING_SIZE, "%02lx", value);
  else if (16 >= bits)
    snprintf(scratchstr, SCRATCH_STRING_SIZE, "%04lx", value);
  else if (24 >= bits)
    snprintf(scratchstr, SCRATCH_STRING_SIZE, "%06lx", value);
  else
    snprintf(scratchstr, SCRATCH_STRING_SIZE, "%08lx", value);

  scratchstr[SCRATCH_STRING_SIZE] = 0;

  UART_QueueSend(scratchstr);
}



// Polling entry point for handling messages sent to the host.

void PollHostReporting()
{
  static uint32_t prev_dval_input, prev_dval_output, prev_dval_user;
  uint32_t dval_input, dval_output, dval_user;

  if (report_changes)
  {
    // Read the current I/O line values.
    // NOTE - We don't need a lock for this.
    dval_input = GetDIOBits(DIO_REG_INPUT);
    dval_output = GetDIOBits(DIO_REG_OUTPUT);
    dval_user = GetDIOBits(DIO_REG_USER);

    // See if any of our register values have changed.
    // If so, report them to the user.

    if ( force_output || (dval_input != prev_dval_input) )
    {
      prev_dval_input = dval_input;

      UART_QueueSend_P(PSTR("I: "));
      PrintHexValue(dval_input, GetDIOCount(DIO_REG_INPUT));
      UART_QueueSend_P(PSTR("\r\n"));
    }

    if ( force_output || (dval_output != prev_dval_output) )
    {
      prev_dval_output = dval_output;

      UART_QueueSend_P(PSTR("O: "));
      PrintHexValue(dval_output, GetDIOCount(DIO_REG_OUTPUT));
      UART_QueueSend_P(PSTR("\r\n"));
    }

    if ( force_output || (dval_user != prev_dval_user) )
    {
      prev_dval_user = dval_user;

      UART_QueueSend_P(PSTR("U: "));
      PrintHexValue(dval_user, GetDIOCount(DIO_REG_USER));
      UART_QueueSend_P(PSTR("\r\n"));
    }


    // Reset the output-force flag. Any startup output has now happened.
    force_output = false;
  }
}



// Dumps full config register state to the serial port (debug command).

// FIXME - Don't stack-allocate something this big.
uint8_t regvals[256];

void DebugDumpRegState()
{
  int idx;

  for (idx = 0; idx < 256; idx++)
    regvals[idx] = 0x00;

  ATOMIC_BLOCK(ATOMIC_RESTORESTATE)
  {
    for (idx = 0x20; idx <= 0xff; idx++)
      regvals[idx] = _SFR_MEM8(idx);
  }

  UART_QueueSend_P(PSTR("AVR configuration register contents:\r\n\r\n"));

  for (idx = 0; idx < 256; idx++)
  {
    if (0 == (idx & 0x03))
      UART_PrintChar(' ');

    UART_PrintChar(' ');

    UART_PrintHex8(regvals[idx]);

    if (0 == ((idx + 1) & 0x0f))
      UART_QueueSend_P(PSTR("\r\n"));

    if (0 == ((idx + 1) & 0x3f))
      UART_QueueSend_P(PSTR("\r\n"));
  }

  UART_QueueSend_P(PSTR("Register contents ends.\r\n"));
}



//
// This is the end of the file.
