#load "print.p";

Arinc429 :: struct {
    Id :: enum (u32) {
        Altitude             :: 0o076;
        MFD_DoubleStageKnob1 :: 0o136;
        MFD_DoubleStageKnob2 :: 0o137;
        MFD_Lsk1Lsk4         :: 0o141;
        MFD_Lsk5Bsk2         :: 0o142;
        MFD_Lsk7Lsk10        :: 0o143;
        MFD_Lsk11Bsk4        :: 0o144;
        MFD_Bsk5Msk2         :: 0o145;
        MagneticVariation    :: 0o147;
        GreenwichMeanTime    :: 0o150;
        Date                 :: 0o260;
        LatitudeCoarse       :: 0o310;
        LongitudeCoarse      :: 0o311;
        GroundSpeed          :: 0o312;
        TrueHeading          :: 0o314;
        LatitudeFine         :: 0o322;
        LongitudeFine        :: 0o323;
    }

    SSM :: enum (u32) {
        // BNR Data
        BNR_FailureWarning  :: 0b00;
        BNR_NoComputedData  :: 0b01;
        BNR_FunctionalTest  :: 0b10;
        BNR_NormalOperation :: 0b11;

        // BCD Data
        BCD_Plus  :: 0b00;
        BCD_North :: 0b00;
        BCD_East  :: 0b00;
        BCD_Right :: 0b00;
        BCD_To    :: 0b00;
        BCD_Above :: 0b00;
        BCD_NoComputedData :: 0b01;
        BCD_FunctionalTest :: 0b10;
        BCD_Minus :: 0b11;
        BCD_South :: 0b11;
        BCD_West  :: 0b11;
        BCD_Left  :: 0b11;
        BCD_From  :: 0b11;
        BCD_Below :: 0b11;

        // Discrete Data
        Discrete_VerifiedData    :: 0b00;
        Discrete_NormalOperation :: 0b00;
        Discrete_NoComputedData  :: 0b01;
        Discrete_FunctionalTest  :: 0b10;
        Discrete_FailureWarning  :: 0b11;
    }

    // Each MFD key is encoded using 4 bits in a discrete label:
    //   1. Validity of the key (press)
    //   2. Whether the key is currently being pressed
    //   3 / 4. Indication of the press duration
    MFD_KeyStatus :: enum (u32) {
        Released :: 0b1000;
        Short    :: 0b1001;
        Medium   :: 0b1010;
        Long     :: 0b1011;
        Pressed  :: 0b1100;
    }

    Parity :: enum (u32) {
        Even :: 0;
        Odd  :: 1;
    }
    
    Label :: struct {
        raw: u32;

        /* --------------------------------------------- Setters --------------------------------------------- */
        
        set_raw :: (label: *Label, value: u32, first_bit: u32, last_bit: u32) {
            // Make sure the bit indices are valid
            if !ensure_indices_in_bounds(first_bit, last_bit) {
                return;
            }

            // Make sure the value actually fits into the available number of bits
            if value != 0 && highest_bit_set(value) > last_bit - first_bit {
                error("The raw value '%' does not fit into % bits.", format_int(value, .Hexadecimal, false, true, 0), last_bit - first_bit + 1);
                return;
            }

            // Make sure we're not overwriting some data in the label
            existing_raw := clear_except_range(label.raw, first_bit, last_bit);
            if existing_raw != 0 {
                error("The bits '%'-'%' have already been occupied in the label.", first_bit, last_bit);
                return;
            }
            
            // Combine the value into the label's raw value
            label.raw |= value << (first_bit - 1);
        }

        set_id :: (label: *Label, id: Id) {
            Label.set_raw(label, id, 1, 8);
        }

        set_ssm :: (label: *Label, ssm: SSM) {
            Label.set_raw(label, ssm, 30, 31);
        }

        set_sdi :: (label: *Label, sdi: u8) {
            Label.set_raw(label, sdi, 9, 10);
        }
        
        set_parity :: (label: *Label, parity: Parity) {
            bit := ifx count_bits_set(label.raw) % 2 == 0 then parity else !parity;
            Label.set_raw(label, bit, 32, 32);
        }

        set_bnr :: (label: *Label, value: f64, resolution: f64, first_bit: u32, last_bit: u32, sign_bit: u32) {
            bit_count := last_bit - first_bit + 1;
            
            // Get the encoded value in units of resolution.
            encoded_limit: s64 = (1 << bit_count) - 1;
            encoded: s64 = cast(s64) (value / resolution);
            if encoded < -encoded_limit || encoded > encoded_limit {
                error("The BNR value '%' does not fit into % bits with % as resolution (limit: %).", value, bit_count, resolution, resolution * xx encoded_limit);
                return;
            }

            // Remove the sign bit
            signed := encoded < 0;
            if encoded < 0 encoded = -encoded;
            
            // Set the raw data
            Label.set_raw(label, encoded, first_bit, last_bit);

            // Set the sign bit
            Label.set_raw(label, signed, sign_bit, sign_bit);
        }

        set_bcd_digit :: (label: *Label, digit: u32, first_bit: u32, last_bit: u32) {
            bit_count := last_bit - first_bit + 1;
            
            // Make sure the digit actually fits into the bits
            encoded_limit: s64 = (1 << bit_count) - 1;
            if digit < 0 || digit > encoded_limit {
                error("The BCD digit '%' does not fit into % bits (limit: %).", digit, bit_count, encoded_limit);
                return;
            }

            // Set the raw data
            Label.set_raw(label, digit, first_bit, last_bit);
        }

        set_bcd_value_with_radix :: (label: *Label, value: u32, radix: u32, first_bit: u32, last_bit: u32) {
            // Calculate the bits per digit
            if radix != 10 {
                error("The BCD radix '%' is unsupported (only 10 is for now).", radix);
                return;
            }

            bits_per_digit: u32 = 4; // Hardcoded for radix == 10

            // Add each digit to the label until we run out of space
            remaining_value := value;
            start_bit := first_bit;
            while start_bit <= last_bit {
                end_bit := ifx start_bit + bits_per_digit - 1 > last_bit then last_bit else start_bit + bits_per_digit - 1;
                Label.set_bcd_digit(label, remaining_value % radix, start_bit, end_bit);
                remaining_value /= radix;
                start_bit = end_bit + 1;
            }

            if remaining_value != 0 {
                bit_count := last_bit - first_bit + 1;
                error("The BCD value '%' does not fit into % bits with radix %.", value, bit_count, radix);
            }
        }
        
        set_discrete :: (label: *Label, value: u32, first_bit: u32, last_bit: u32) {
            Label.set_raw(label, value, first_bit, last_bit);
        }

        set_discrete_bit :: (label: *Label, value: bool, bit: u32) {
            Label.set_raw(label, value, bit, bit);
        }



        /* ---------------------------------------------- Getters --------------------------------------------- */
        
        get_raw :: (label: *Label, first_bit: u32, last_bit: u32) -> u32 {
            // Make sure the bit indices are valid
            if !ensure_indices_in_bounds(first_bit, last_bit) {
                return 0;
            }

            result := clear_except_range(label.raw, first_bit, last_bit);
            result >>= first_bit - 1;
            return result;
        }

        get_id :: (label: *Label) -> Id {
            return xx Label.get_raw(label, 1, 8);
        }

        get_ssm :: (label: *Label) -> SSM {
            return xx Label.get_raw(label, 30, 31);
        }

        get_sdi :: (label: *Label) -> u8 {
            return Label.get_raw(label, 9, 10);
        }

        get_parity :: (label: *Label) -> u8 {
            return Label.get_raw(label, 32, 32);
        }

        get_bnr :: (label: *Label, resolution: f64, first_bit: u32, last_bit: u32, sign_bit: u32) -> f64 {
            encoded := Label.get_raw(label, first_bit, last_bit);

            result := cast(f64) encoded * resolution;
            if Label.get_raw(label, sign_bit, sign_bit) result = -result;
            
            return result;
        }

        get_bcd_digit :: (label: *Label, first_bit: u32, last_bit: u32) -> u32 {
            return Label.get_raw(label, first_bit, last_bit);
        }

        get_bcd_value_with_radix :: (label: *Label, radix: u32, first_bit: u32, last_bit: u32) -> u32 {
            // Calculate the bits per digit
            if radix != 10 {
                error("The BCD radix '%' is unsupported (only 10 is for now).", radix);
                return 0;
            }

            bits_per_digit: u32 = 4; // Hardcoded for radix == 10

            // Read each digit to the label until we run out of space
            result: u32 = 0;
            power: u32 = 1;
            start_bit := first_bit;

            while start_bit <= last_bit {
                end_bit := ifx start_bit + bits_per_digit - 1 > last_bit then last_bit else start_bit + bits_per_digit - 1;
                result += Label.get_bcd_digit(label, start_bit, end_bit) * power;
                power *= radix;
                start_bit = end_bit + 1;
            }
            
            return result;
        }

        get_discrete :: (label: *Label, first_bit: u32, last_bit: u32) -> u32 {
            return Label.get_raw(label, first_bit, last_bit);
        }

        get_discrete_bit :: (label: *Label, bit: u32) -> bool {
            return Label.get_raw(label, bit, bit);
        }
    }
}



#file_scope

error :: (format: string, args: ..Any) {
    print("[ARINC]: ");
    print(format, ..args);
    print("\n");
}

ensure_indices_in_bounds :: (first_bit: u32, last_bit: u32) -> bool {
    all_valid := first_bit >= 1 && first_bit <= 32 &&
        last_bit >= 1 && last_bit <= 32 &&
        first_bit <= last_bit;

    if !all_valid error("The passed bit indices '%'-'%' are out of bounds.", first_bit, last_bit);

    return all_valid;
}

clear_except_range :: (value: u32, first_bit: u32, last_bit: u32) -> u32 {
    result := value;
    result &= 0xffffffff >> (32 - last_bit);
    result &= 0xffffffff << (first_bit - 1);
    return result;
}


/*
main :: () -> s32 {
    #using Arinc429;

    // Ground Speed
    {
        label := Label.{};
        Label.set_id(*label, .GroundSpeed);
        Label.set_ssm(*label, .BNR_NormalOperation);
        Label.set_sdi(*label, 0b00);
        Label.set_bnr(*label, 140, 4096 / 32768, 14, 28, 29);
        Label.set_parity(*label, .Odd);
        print("GroundSpeed: % (raw: %)\n", Label.get_bnr(*label, 4096 / 32768, 14, 28, 29), format_int(label.raw, .Hexadecimal, false, true, 0));
    }

    // Time
    {
        label := Label.{};
        Label.set_id(*label, .Date);
        Label.set_ssm(*label, .BCD_Plus);
        Label.set_sdi(*label, 0b00);
        Label.set_bcd_value_with_radix(*label, 24, 10, 11, 18);
        Label.set_bcd_value_with_radix(*label, 11, 10, 19, 23);
        Label.set_bcd_value_with_radix(*label, 27, 10, 24, 29);
        Label.set_sdi(*label, 0b01);
        Label.set_parity(*label, .Odd);        
        print("Date: %, %, % (raw: %)\n", Label.get_bcd_value_with_radix(*label, 10, 11, 18), Label.get_bcd_value_with_radix(*label, 10, 19, 23), Label.get_bcd_value_with_radix(*label, 10, 24, 29), format_int(label.raw, .Hexadecimal, false, true, 0));
    }

    // Outer Rotary Label
    {
        label := Label.{};
        Label.set_id(*label, .MFD_DoubleStageKnob2);
        Label.set_ssm(*label, .BNR_NormalOperation);
        Label.set_bnr(*label, 0, 1, 16, 28, 29);  // Rotation in tics
        Label.set_discrete_bit(*label, true, 15); // Rotation validity
        Label.set_discrete(*label, MFD_KeyStatus.Short, 11, 14); // Press validity, down, press duration
        print("DoubleStageKnob2: %, %, %, % (raw: %)\n", Label.get_discrete_bit(*label, 15), Label.get_discrete_bit(*label, 14), Label.get_discrete_bit(*label, 13), Label.get_discrete(*label, 11, 13), format_int(label.raw, .Hexadecimal, false, true, 0));
    }

    return 0;
}
*/
