# frozen_string_literal: true

module R80
  # Based on some parts of MAME's Z80 implementation (BSD licensed)
  # See https://github.com/mamedev/mame/blob/master/src/devices/cpu/z80/z80.cpp
  # at line 3320, 796, etc

  # Generate & provide lookup tables for Z80 flags
  class Tables
    attr_reader :sz, :sz_bit, :szp, :szhv_inc, :szhv_dec, :szhvc_add, :szhvc_sub, :szhvc

    def initialize
      @sz = [] # zero and sign flags
      @sz_bit = [] # zero, sign and parity/overflow (=zero) flags for BIT opcode
      @szp = [] # zero, sign and parity flags
      @szhv_inc = [] # zero, sign, half carry and overflow flags INC r8
      @szhv_dec = [] # zero, sign, half carry and overflow flags DEC r8
      @szhvc_add = []
      @szhvc_sub = []
      # rubocop:disable Layout
      @dd_fd_prefixable = [
                                                              0x09,
                                                              0x19,
              0x21, 0x22, 0x23, 0x24, 0x25, 0x26,             0x29, 0x2a, 0x2b, 0x2c, 0x2d, 0x2e,
                                0x34, 0x35, 0x36,             0x39,
                                0x44, 0x45, 0x46,                               0x4c, 0x4d, 0x4e,
                                0x54, 0x55, 0x56,                               0x5c, 0x5d, 0x5e,
        0x60, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6a, 0x6b, 0x6c, 0x6d, 0x6e, 0x6f,
        0x70, 0x71, 0x72, 0x73, 0x74, 0x75,       0x77,                         0x7c, 0x7d, 0x7e,
                                0x84, 0x85, 0x86,                               0x8c, 0x8d, 0x8e,
                                0x94, 0x95, 0x96,                               0x9c, 0x9d, 0x9e,
                                0xa4, 0xa5, 0xa6,                               0xac, 0xad, 0xae,
                                0xb4, 0xb5, 0xb6,                               0xbc, 0xbd, 0xbe,
                                                                          0xcb,

              0xe1,       0xe3,       0xe5,                   0xe9,
                                                              0xf9
      ]
      # rubocop:enable Layout

      # Set up the two 132K lookup tables
      offset = 0
      (0x00..0xFF).each do |oldval|
        (0x00..0xFF).each do |newval|
          # add or adc w/o carry set
          val = newval - oldval
          @szhvc_add[offset] = if newval.zero?
                                 Z_MASK
                               else
                                 ((newval & 0x80).zero? ? 0 : S_MASK)
                               end
          @szhvc_add[offset] |= (newval & (Y_MASK | X_MASK))
          @szhvc_add[offset] |= H_MASK if (newval & 0x0F) < (oldval & 0x0F)
          @szhvc_add[offset] |= C_MASK if newval < oldval
          @szhvc_add[offset] |= V_MASK unless ((val ^ oldval ^ 0x80) & (val ^ newval) & 0x80).zero?

          # adc with carry set
          val = newval - oldval - 1
          @szhvc_add[256 * 256 + offset] = if newval.zero?
                                             Z_MASK
                                           else
                                             ((newval & 0x80).zero? ? 0 : S_MASK)
                                           end
          @szhvc_add[256 * 256 + offset] |= newval & (Y_MASK | X_MASK)
          @szhvc_add[256 * 256 + offset] |= H_MASK if (newval & 0x0F) <= (oldval & 0x0F)
          @szhvc_add[256 * 256 + offset] |= C_MASK if newval <= oldval
          @szhvc_add[256 * 256 + offset] |= V_MASK unless ((val ^ oldval ^ 0x80) & (val ^ newval) & 0x80).zero?

          # cp, sub or sbc w/o carry set
          val = oldval - newval
          @szhvc_sub[offset] = N_MASK | (if newval.zero?
                                           Z_MASK
                                         else
                                           ((newval & 0x80).zero? ? 0 : S_MASK)
                                         end)
          @szhvc_sub[offset] |= newval & (Y_MASK | X_MASK)
          @szhvc_sub[offset] |= H_MASK if (newval & 0x0F) > (oldval & 0x0F)
          @szhvc_sub[offset] |= C_MASK if newval > oldval
          @szhvc_sub[offset] |= V_MASK unless ((val ^ oldval) & (oldval ^ newval) & 0x80).zero?

          # sbc with carry set
          val = oldval - newval - 1
          @szhvc_sub[256 * 256 + offset] = N_MASK | (if newval.zero?
                                                       Z_MASK
                                                     else
                                                       ((newval & 0x80).zero? ? 0 : S_MASK)
                                                     end)
          @szhvc_sub[256 * 256 + offset] |= newval & (Y_MASK | X_MASK)
          @szhvc_sub[256 * 256 + offset] |= H_MASK if (newval & 0x0F) >= (oldval & 0x0F)
          @szhvc_sub[256 * 256 + offset] |= C_MASK if newval >= oldval
          @szhvc_sub[256 * 256 + offset] |= V_MASK unless ((val ^ oldval) & (oldval ^ newval) & 0x80).zero?

          offset += 1
        end
      end

      # Set up the 256 entry lookup tables
      (0x00..0xFF).each do |i|
        p = 0x00
        p += 1 unless (i & 0x01).zero?
        p += 1 unless (i & 0x02).zero?
        p += 1 unless (i & 0x04).zero?
        p += 1 unless (i & 0x08).zero?
        p += 1 unless (i & 0x10).zero?
        p += 1 unless (i & 0x20).zero?
        p += 1 unless (i & 0x40).zero?
        p += 1 unless (i & 0x80).zero?
        @sz[i] = i.zero? ? Z_MASK : (i & S_MASK)
        @sz[i] |= (i & (Y_MASK | X_MASK))
        @sz_bit[i] = i.zero? ? Z_MASK | V_MASK : i & S_MASK
        @sz_bit[i] |= (i & (Y_MASK | X_MASK))
        @szp[i] = @sz[i]
        @szp[i] |= V_MASK if (p & 1).zero?
        @szhv_inc[i] = @sz[i]
        @szhv_inc[i] |= V_MASK if i == 0x80
        @szhv_inc[i] |= H_MASK if (i & 0x0F).zero?
        @szhv_dec[i] = @sz[i] | N_MASK
        @szhv_dec[i] |= V_MASK if i == 0x7F
        @szhv_dec[i] |= H_MASK if (i & 0x0F) == 0x0F
      end
    end

    def can_dd_fd_prefix?(opcode)
      @dd_fd_prefixable.include?(opcode)
    end
  end
end
