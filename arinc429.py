from enum import IntEnum

class Id(IntEnum):
    Altitude          = 0o076
    DoubleStageKnob1  = 0o136
    DoubleStageKnob2  = 0o137
    Lsk1Lsk4          = 0o141 # @Incomplete: Preface these with MFD?
    Lsk5Bsk2          = 0o142
    Lsk7Lsk10         = 0o143
    Lsk11Bsk4         = 0o144
    Bsk5Msk2          = 0o145
    MagneticVariation = 0o147
    GreenwichMeanTime = 0o150
    Date              = 0o260
    LatitudeCoarse    = 0o310
    LongitudeCoarse   = 0o311
    GroundSpeed       = 0o312
    TrueHeading       = 0o314
    LatitudeFine      = 0o322
    LongitudeFine     = 0o323


class SSM(IntEnum):
    # BNR Data
    BNR_FailureWarning  = 0b00
    BNR_NoComputedData  = 0b01
    BNR_FunctionalTest  = 0b10
    BNR_NormalOperation = 0b11

    # BCD Data
    BCD_Plus  = 0b00
    BCD_North = 0b00
    BCD_East  = 0b00
    BCD_Right = 0b00
    BCD_To    = 0b00
    BCD_Above = 0b00
    BCD_NoComputedData = 0b01
    BCD_FunctionalTest = 0b10
    BCD_Minus = 0b11
    BCD_South = 0b11
    BCD_West  = 0b11
    BCD_Left  = 0b11
    BCD_From  = 0b11
    BCD_Below = 0b11

    # Discrete Data
    Discrete_VerifiedData    = 0b00
    Discrete_NormalOperation = 0b00
    Discrete_NoComputedData  = 0b01
    Discrete_FunctionalTest  = 0b10
    Discrete_FailureWarning  = 0b11

# @Incomplete: Rename to MFD_KeyStatus
# @Incomplete: Maybe include the button validity flag in this?
class ButtonStatus(IntEnum):
    Released = 0b000
    Short    = 0b001
    Medium   = 0b010
    Long     = 0b011
    Pressed  = 0b100

class Parity(IntEnum):
    Even = 0
    Odd  = 1

# @Incomplete: Implement getters for all the existing setters
class Label:
    raw: int = 0

    # ----------------------------------------------- Setters -----------------------------------------------

    def set_raw(self, value: int, first_bit: int, last_bit: int):
        # Make sure the bit indices are valid
        if not arinc429_ensure_indices_in_bounds(first_bit, last_bit):
            return

        # Make sure the value actually fits into the available number of bits
        if value != 0 and arinc429_highest_bit_set(value) > last_bit - first_bit:
            arinc429_report_error("The raw value '" + hex(value) + "' does not fit into " + str(last_bit - first_bit + 1) + " bits.")
            return

        # Make sure we're not overwriting some data in the label
        existing_raw = arinc429_clear_except_range(self.raw, first_bit, last_bit)
        if existing_raw != 0:
            arinc429_report_error("The bits '" + str(first_bit) + "'-'" + str(last_bit) + "' have already been occupied in the label.")
            return

        # Combine the value into the label's raw value
        self.raw |= value << (first_bit - 1)

    def set_id(self, id: Id):
        self.set_raw(id, 1, 8)

    def set_ssm(self, ssm: SSM):
        self.set_raw(ssm, 30, 31)

    def set_sdi(self, sdi: int):
        self.set_raw(sdi, 9, 10)

    def set_parity(self, parity: Parity):
        bit = (parity) if arinc429_count_bits_set(self.raw) % 2 == 0 else (not parity)
        self.set_raw(bit, 32, 32)

    def set_bnr(self, value: float, resolution: float, first_bit: int, last_bit: int, sign_bit: int):
        bit_count = last_bit - first_bit + 1

        # Get the encoded value in units of resolution
        encoded_limit = (1 << bit_count) - 1
        encoded = int(value / resolution)
        if encoded < -encoded_limit or encoded > encoded_limit:
            arinc429_report_error("The BNR value '" + str(value) + "' does not fit into " + str(bit_count) + " with " + str(resolution) + " as resolution (limit: " + str(resolution * encoded_limit) + ").")
            return

        # Remove the sign bit
        signed = encoded < 0
        if encoded < 0:
            encoded = -encoded

        # Set the raw data
        self.set_raw(encoded, first_bit, last_bit)

        # Set the sign bit
        self.set_raw(signed, sign_bit, sign_bit)

    def set_bcd_digit(self, digit: int, first_bit: int, last_bit: int):
        bit_count = last_bit - first_bit + 1

        # Make sure the digit actually fits into the bits
        encoded_limit = (1 << bit_count) - 1
        if digit < 0 or digit > encoded_limit:
            arinc429_report_error("The BCD digit '" + str(digit) + "' does not fit into " + str(bit_count) + " bits (limit: " + str(encoded_limit) + ").")
            return

        # Set the raw data
        self.set_raw(digit, first_bit, last_bit)

    def set_bcd_value_with_radix(self, value: int, radix: int, first_bit: int, last_bit: int):
        # Calculate the bits per digit
        if radix != 10:
            arinc429_report_error("The BCD radix '" + str(radix) + "' is unnsupported (only 10 is for now).")
            return

        bits_per_digit = 4 # Hardcoded for radix == 10

        # Add each digit to the label until we run out of space
        remaining_value = value
        start_bit = first_bit
        while start_bit <= last_bit:
            end_bit = last_bit if start_bit + bits_per_digit - 1 > last_bit else start_bit + bits_per_digit - 1
            self.set_bcd_digit(remaining_value % radix, start_bit, end_bit)
            remaining_value //= radix
            start_bit = end_bit + 1

        if remaining_value:
            arinc429_report_error("The BCD value '" + str(value) + "' does not fit into " + str(bit_count) + " bits with radix " + str(radix) + ".")

    def set_discrete(self, value: int, first_bit: int, last_bit: int):
        self.set_raw(value, first_bit, last_bit)

    def set_discrete_bit(self, value: bool, bit: int):
        self.set_raw(value, bit, bit)


        
# -------------------------------------------- File Scope Helpers --------------------------------------------

def arinc429_highest_bit_set(value: int) -> int:
    position = 0
    while value:
        position += 1
        value >>= 1
    return position - 1

def arinc429_count_bits_set(value: int) -> int:
    count = 0
    while value:
        count += 1
        value &= value - 1
    return count

def arinc429_report_error(msg: str):
    print("[ARINC]: " + msg)

def arinc429_ensure_indices_in_bounds(first_bit: int, last_bit: int) -> bool:
    all_valid = first_bit >= 1 and first_bit <= 32 and last_bit >= 1 and last_bit <= 32 and first_bit <= last_bit

    if not all_valid:
        arinc429_report_error("The passed bit indices '" + str(first_bit) + "'-'" + str(last_bit) + "' are out of bounds.")

    return all_valid

def arinc429_clear_except_range(value: int, first_bit: int, last_bit: int) -> int:
    result = value
    result &= 0xffffffff >> (32 - last_bit)
    result &= 0xffffffff << (first_bit - 1)
    return result



# -------------------------------------------------- Tests --------------------------------------------------

# @Incomplete: Make sure we properly report all errors here...

def arinc429_test_ground_speed_label():
    label = Label()
    label.set_id(Id.GroundSpeed)
    label.set_ssm(SSM.BNR_NormalOperation)
    label.set_sdi(0b00)
    label.set_bnr(140, 4096 / 32768, 14, 28, 29)
    label.set_parity(Parity.Odd)
    print("GroundSpeed: " + hex(label.raw))

def arinc429_test_date_label():
    label = Label()
    label.set_id(Id.Date)
    label.set_ssm(SSM.BCD_Plus)
    label.set_bcd_value_with_radix(24, 10, 11, 18)
    label.set_bcd_value_with_radix(11, 10, 19, 23)
    label.set_bcd_value_with_radix(27, 10, 24, 29)
    label.set_sdi(0b01)
    label.set_parity(Parity.Odd)
    print("Date: " + hex(label.raw))

def arinc429_test_outer_rotary_label():
    label = Label()
    label.set_id(Id.DoubleStageKnob2)
    label.set_ssm(SSM.BNR_NormalOperation)
    label.set_bnr(0, 1, 16, 28, 29)
    label.set_discrete_bit(True, 15)
    label.set_discrete_bit(True, 14)
    label.set_discrete_bit(False, 13)
    label.set_discrete(ButtonStatus.Short, 11, 13)
    print("DoubleStageKnob2: " + hex(label.raw))
    
arinc429_test_ground_speed_label()
arinc429_test_date_label()
arinc429_test_outer_rotary_label()
