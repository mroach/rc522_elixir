defmodule RC522 do
  @moduledoc """
  I apologise in advance for the lack of documentation in this module.
  I mostly tried to port code from the C, C++, and Python versions of this driver
  and they had little to no documentation to explain why things were happening.

  As I figure out what's actually happening and why, I'll document it.

  Also apologies for commented-out code. It's stuff I'm not sure I need but
  don't want to get rid of it yet until I figure out what's going on.
  """

  use Bitwise
  require Logger
  alias Circuits.SPI
  alias Circuits.GPIO

  # MFRC522 docs 9.2 "Register Overview"
  @register %{
    command:       0x01,
    comm_ien:      0x02,  # toggle interrupt request control bits
    div_ien:       0x03,  # toggle interrupt request control bits
    comm_irq:      0x04,  # interrupt request bits
    div_irq:       0x05,  # interrupt request bits
    error:         0x06,  # error status of last command executed
    status_1:      0x07,  # communication status bits
    status_2:      0x08,  # receiver and transmitter status bits
    fifo_data:     0x09,  # 64 byte FIFO buffer
    fifo_level:    0x0A,  # number of bytes stored in the FIFO register
    water_level:   0x0B,  # level for FIFO under/overflow warning
    control:       0x0C,  # miscellaneous control registers
    bit_framing:   0x0D,
    coll:          0x0E,

    mode:          0x11,  # general mode for transmit and receive
    tx_mode:       0x12,  # transmission data rate and framing
    rx_mode:       0x13,  # reception data rate and framing
    tx_control:    0x14,  # control logical behaviour of the antenna TX1 and TX2 pins
    tx_auto:       0x15,  # control setting of transmission moduleation
    tx_sel:        0x16,  # select internal sources for the antenna driver
    rx_sel:        0x17,  # receiver settings
    rx_threshold:  0x18,  # thresholds for bit decoder
    demod:         0x19,  # demodulator settings

    crc_result_h:  0x21,  # show the MSB and LSB values of the CRC calculation
    crc_result_l:  0x22,  # show the MSB and LSB values of the CRC calculation
    mod_width:     0x24,

    t_mode:        0x2A,  # define settings for the internal timer
    t_prescaler:   0x2B,  # define settings for the internal timer
    t_reload_h:    0x2C,  # define the 16-bit timer reload value
    t_reload_l:    0x2D,

    version:       0x37   # show software version
  }
  @valid_registers Map.values(@register)

  # MFRC522 documentation 10.3 "Command overview"
  # Use with the "command" register to send commands to the PCD
  # PCD = Proximity Coupling Device. The RFID reader itself.
  @command %{
    idle:          0x00,  # no action, cancels current command execution
    mem:           0x01,  # stores 25 bytes into the internal buffer
    gen_rand_id:   0x02,  # generates a 10-byte random ID number
    calc_crc:      0x03,  # activates the CRC coprocessor or performs a self test
    transmit:      0x04,  # transmits data from the FIFO buffer
    no_cmd_change: 0x07,  # can be used to modify the command register bits without affecting the command
    receive:       0x08,  # activates the receiver circuits
    transceive:    0x0C,  # transmits data from the FIFO buffer to antenna and automatically activates the receiver after transmission
    mifare_auth:   0x0E,  # perform standard MIFARE auth as a reader
    soft_reset:    0x0F   # perform a soft reset
  }

  # Proximity Integrated Circuit Card (PICC)
  # The RFID Card or Tag using the ISO/IEC 14443A interface, for example Mifare or NTAG203.
  @picc %{
    request_idl:  0x26, # REQuest command, Type A. Invites PICCs in state IDLE to go to READY and prepare for anticollision or selection. 7 bit frame.
    request_all:  0x52, # Wake-UP command, Type A. Invites PICCs in state IDLE and HALT to go to READY(*) and prepare for anticollision or selection. 7 bit frame.
    anticoll:     0x93  # Anti collision/Select, Cascade Level 1
  }

  # 9.3.2.5 Transmission control
  @tx_control %{
    antenna_on: 0x03
  }

  @gpio_reset_pin 25

  def initialize(spi) do
    hard_reset()

    spi
    |> write(@register.t_mode, 0x8D)
    |> write(@register.t_prescaler, 0x3E)
    |> write(@register.t_reload_l, 0x30)
    |> write(@register.t_reload_h, 0x00)
    |> write(@register.tx_auto, 0x40)
    |> write(@register.mode, 0x3D)
    |> antenna_on
  end

  def halt(spi) do
    # TODO: implement. some code used this to tell the PCD (and/or PICC)
    # that we're done doing things with it.
    spi
  end

  @doc """
  See MFRC522 docs 9.3.4.8
  Bits 7 to 4 are the chiptype. Should always be "9" for MFRC522
  Bits 0 to 3 are the version
  """
  def hardware_version(spi) do
    data = read(spi, @register.version)
    %{
      chip_type: chip_type((data &&& 0xF0) >>> 4),
      version: data &&& 0x0F
    }
  end

  def read_tag_id(spi) do
    request(spi, @picc.request_idl)
    anticoll(spi)
    #uid
  end

  def request(spi, request_mode) do
    # 0x07 start transmission
    write(spi, @register.bit_framing, 0x07)
    to_card(spi, @command.transceive, request_mode)
  end

  def to_card(spi, command, data) do
    # THESE ARE ONLY FOR COMMAND == transceive
    # irq_en = 0x77
    # wait_irq = 0x30   # RxIRq and IdleIRq

    spi
    |> write(@register.command, @command.idle)        # stop any active commands
    #|> write(@register.comm_irq, 0x7F)                # clear all interrupt request bits
    |> write(@register.fifo_level, 0x80)              # FlushBuffer = 1, FIFO init
    #|> write(@register.comm_ien, bor(0x80, irq_en))
    #|> clear_bit_mask(@register.comm_irq, 0x80)
    #|> set_bit_bask(@register.fifo_level, 0x80)
    |> write(@register.fifo_data, data)
    |> write(@register.command, command)

    if command == @command.transceive do
      set_bit_bask(spi, @register.bit_framing, 0x80)
    end

    # TODO: replace this with that loop that reads the Comm IRQ and does stuff
    :timer.sleep(50)

    data = read_fifo(spi)
    {:ok, data}
  end

  def anticoll(spi) do
    write(spi, @register.bit_framing, 0x00)

    #{status, back_data, back_bits} =
    to_card(spi, @command.transceive, [@picc.anticoll, 0x20])

    # TODO: implement serial number check

    #{status, back_data}
  end

  def hard_reset do
    {:ok, gpio} = GPIO.open(@gpio_reset_pin, :output)
    GPIO.write(gpio, 1)
    :timer.sleep(50)
    GPIO.close(gpio)
  end

  def soft_reset(spi), do: write(spi, @register.command, @command.soft_reset)

  def last_error(spi), do: read(spi, @register.error) &&& 0x1B

  def read_fifo(spi) do
    fifo_byte_count = read(spi, @register.fifo_level)
    read(spi, @register.fifo_data, fifo_byte_count)
  end

  def antenna_on(spi) do
    set_bit_bask(spi, @register.tx_control, @tx_control.antenna_on)
  end

  def antenna_off(spi) do
    clear_bit_mask(spi, @register.tx_control, @tx_control.antenna_on)
  end

  def set_bit_bask(spi, register, mask) when register in @valid_registers do
    state = read(spi, register)
    write(spi, register, bor(state, mask))
  end

  def clear_bit_mask(spi, register, mask) when register in @valid_registers do
    state = read(spi, register)
    value = state &&& bnot(mask)
    write(spi, register, value)
  end

  @doc """
  Write one or more bytes to the given register
  """
  def write(spi, register, value) when is_integer(value) do
    write(spi, register, [value])
  end
  def write(spi, register, values)
    when register in @valid_registers
    and is_list(values) do

    register = (register <<< 1) &&& 0x7E

    Enum.each(values, fn value ->
      {:ok, _return} = SPI.transfer(spi, <<register, value>>)
    end)

    spi
  end

  @doc """
  Read the single byte value of the given register.
  The result of `SPI.transfer/2` is always the same length as the input.
  Since we have to send the register number and `0x00`, it means we always
  get two bytes back. The first byte appears to often be `0`, but sometimes other
  small values. But they have yet to seem relevant, so we discard it and consider
  only the second byte to be the value.
  """
  def read(spi, register) when register in @valid_registers do
    register = bor(0x80, (register <<< 1) &&& 0x7E)
    {:ok, <<_, value>>} = SPI.transfer(spi, <<register, 0x00>>)
    value
  end

  @doc """
  Reads `bytes` number of bytes from the `register`. Returned as a list
  """
  def read(spi, register, bytes) when register in @valid_registers do
    Enum.map(1..bytes, fn _byte_index -> read(spi, register) end)
  end

  def card_id_to_number(data) do
    data
    |> Enum.take(5) # should only be five blocks, but just be sure
    |> Enum.reduce(0, fn x, acc -> acc * 256 + x end)
  end

  defp chip_type(9), do: :mfrc522
  defp chip_type(type), do: "unknown_#{ type }"

  def card_type(0x04), do: :uid_incomplete
  def card_type(0x09), do: :mifare_mini
  def card_type(0x08), do: :mifare_1k
  def card_type(0x18), do: :mifare_4k
  def card_type(0x00), do: :mifare_ul
  def card_type(0x10), do: :mifare_plus
  def card_type(0x11), do: :mifare_plus
  def card_type(0x01), do: :tnp3xxx
  def card_type(0x20), do: :iso_14443_4
  def card_type(0x40), do: :iso_18092
  def card_type(_), do: :unknown
end
