# frozen_string_literal: true

require_relative 'io'
require_relative 'memory'
require_relative 'numbers'
require_relative 'registers'
require_relative 'tables'

module R80
  # Keep track of the current opcode prefix, which affects if a given instruction
  # should use HL or IX or IY.
  module Prefix
    NONE = 0x00 # No prefix currently active, so use HL
    DD = 0xDD   # DD prefix is currently active, so use IX
    FD = 0xFD   # FD prefix is currently active, so use IY
  end

  # A complete-but-minimal Z80 system
  class System
    attr_reader :running, :registers, :memory # To help with unit tests

    def initialize(ram_size, initial_pc, cpm_stub: false)
      @starting = true
      @running = true
      @memory = Memory.new(ram_size)
      @registers = Registers.new(initial_pc)
      @io = Io.new
      @tables = Tables.new
      @prefix = Prefix::NONE

      @prefix_to_regsym = {}
      @prefix_to_regsym[Prefix::NONE] = :hl
      @prefix_to_regsym[Prefix::DD] = :ix
      @prefix_to_regsym[Prefix::FD] = :iy

      @handlers = {}
      @handlers[0x00] = method(:op_nop)
      @handlers[0x02] = method(:op_ld_bci_a)
      @handlers[0x07] = method(:op_rlca)
      @handlers[0x08] = method(:op_exafaf)
      @handlers[0x0A] = method(:op_ld_a_bc)
      @handlers[0x0F] = method(:op_rrca)
      @handlers[0x10] = method(:op_djnz)
      @handlers[0x12] = method(:op_ld_dei_a)
      @handlers[0x17] = method(:op_rla)
      @handlers[0x18] = method(:op_jr)
      @handlers[0x1A] = method(:op_ld_a_de)
      @handlers[0x1F] = method(:op_rra)
      @handlers[0x20] = method(:op_jr_nz)
      @handlers[0x22] = method(:op_ld_nnnn_hl)
      @handlers[0x27] = method(:op_daa)
      @handlers[0x28] = method(:op_jr_z)
      @handlers[0x2A] = method(:op_ld_hl_nnnni)
      @handlers[0x2F] = method(:op_cpl)
      @handlers[0x30] = method(:op_jr_nc)
      @handlers[0x32] = method(:op_ld_nnnn_a)
      @handlers[0x37] = method(:op_scf)
      @handlers[0x38] = method(:op_jr_c)
      @handlers[0x3A] = method(:op_ld_a_nnnni)
      @handlers[0x3F] = method(:op_ccf)
      # 0x40 .. 7F -> op_ld_r1_r2  (except for 0x76 which is HALT)
      @handlers[0x76] = method(:op_halt)
      @handlers[0xC3] = method(:op_jp_nnnn)
      @handlers[0xC6] = method(:op_add_a_nn)
      @handlers[0xC9] = method(:op_ret)
      @handlers[0xCB] = method(:op_cb) # Handler for the various CB opcodes
      @handlers[0xCD] = method(:op_call)
      @handlers[0xCE] = method(:op_adc_a_nn)
      @handlers[0xD3] = method(:op_out_nn_a)
      @handlers[0xD6] = method(:op_sub_nn)
      @handlers[0xD9] = method(:op_exx)
      @handlers[0xDB] = method(:op_in_a_nn)
      @handlers[0xDE] = method(:op_sbc_a_nn)
      @handlers[0xE3] = method(:op_ex_spi_hl)
      @handlers[0xE6] = method(:op_and_nn)
      @handlers[0xE9] = method(:op_jp_hli)
      @handlers[0xEB] = method(:op_ex_de_hl)
      @handlers[0xED] = method(:op_ed) # Handler for the various ED opcodes
      @handlers[0xEE] = method(:op_xor_n)
      @handlers[0xF3] = method(:op_di)
      @handlers[0xF6] = method(:op_or_nn)
      @handlers[0xF9] = method(:op_ld_sp_hl)
      @handlers[0xFB] = method(:op_ei)
      @handlers[0xFE] = method(:op_cp_nn)

      # These 3 correspond to r,p,q in table 8.4 of Undocumented Z80
      @sym_from_register_bitmask_r = [:b, :c, :d, :e, :h, :l, nil, :a]
      @sym_from_register_bitmask_p = [:b, :c, :d, :e, :ixh, :ixl, nil, :a]
      @sym_from_register_bitmask_q = [:b, :c, :d, :e, :iyh, :iyl, nil, :a]
      @sym_from_register_bitmask = { Prefix::NONE => @sym_from_register_bitmask_r,
                                     Prefix::DD => @sym_from_register_bitmask_p,
                                     Prefix::FD => @sym_from_register_bitmask_q }

      # This emulation supports a very minimal CP/M BDOS, only sufficient for running ZEXALL.COM
      if cpm_stub
        @cpm_stub = cpm_stub
        # Set a stub for CP/M calls; simply returns from whence it came
        # This is so that zexall.com can be used as a test case
        @memory.set_byte(0x0005, 0xC9) # ret
        @memory.set_word(0x0006, 0xE406) # Some binaries use this to work out where a stack can be placed
      else
        @cpm_stub = false
      end
    end

    # Load the specified binary file into memory at the specified offset
    def load_binary(offset, filename)
      data = File.binread(filename)
      raise 'Binary image too big' if offset + data.size > @memory.size

      @memory[offset, data.size] = data
    end

    # Executes the next instruction (currently pointed at by PC)
    def execute_instruction
      # By definition, a jump (or call or etc) to address zero is termination (unless we're starting there)
      if @registers.pc.zero? && !@starting
        @running = false
        return
      end
      @starting = false

      # Collate any DD/FD prefix sequence
      @prefix = Prefix::NONE
      opcode = next_byte
      while (opcode == 0xDD) || (opcode == 0xFD)
        @prefix = opcode
        opcode = next_byte
      end

      if (@prefix != Prefix::NONE) && !@tables.can_dd_fd_prefix?(opcode)
        # We've encountered one or more DD/FD prefix bytes preceding an opcode which
        # can't be prefixed (more accurately, those prefix bytes have no effect on
        # that opcode. So the DD/FD sequence is discarded in *this* iteration of
        # this method and the unaffected opcode will be handled *next* time through
        # this method.
        @registers.dec(:pc)
        return
      end

      # The current order of checks is a result of some profiling & experiments but
      # there might be scope for further performance improvements at the cost of
      # readability.

      handler = @handlers[opcode]
      return handler.call if handler

      return op_ld_r1_r2(opcode) if (opcode >= 0x40) && (opcode <= 0x7F)
      return op_add_a_r(opcode) if (opcode >= 0x80) && (opcode <= 0x87)
      return op_adc_a_r(opcode) if (opcode >= 0x88) && (opcode <= 0x8F)
      return op_sub_r(opcode) if (opcode >= 0x90) && (opcode <= 0x97)
      return op_sbc_r(opcode) if (opcode >= 0x98) && (opcode <= 0x9F)
      return op_and_r(opcode) if (opcode >= 0xA0) && (opcode <= 0xA7)
      return op_xor_r(opcode) if (opcode >= 0xA8) && (opcode <= 0xAF)
      return op_or_r(opcode) if (opcode >= 0xB0) && (opcode <= 0xB7)
      return op_cp_r(opcode) if (opcode >= 0xB8) && (opcode <= 0xBF)

      bits_cf = opcode & 0xCF
      return op_ld_dd_nnnn(opcode) if bits_cf == 0x01
      return op_inc_dd(opcode) if bits_cf == 0x03
      return op_add_hl_ss(opcode) if bits_cf == 0x09
      return op_dec_dd(opcode) if bits_cf == 0x0B
      return op_pop_qq(opcode) if bits_cf == 0xC1
      return op_push_qq(opcode) if bits_cf == 0xC5

      bits_c7 = opcode & 0xC7
      return op_inc_r(opcode) if bits_c7 == 0x04
      return op_dec_r(opcode) if bits_c7 == 0x05
      return op_ld_r_nn(opcode) if bits_c7 == 0x06
      return op_ret_cc(opcode) if bits_c7 == 0xC0
      return op_jp_cc(opcode) if bits_c7 == 0xC2
      return op_call_cc(opcode) if bits_c7 == 0xC4
      return op_rst_p(opcode) if bits_c7 == 0xC7

      raise "Unimplemented Z80 opcode #{opcode.to_2x}"
    end

    private

    # Helper methods for memory

    # Read and return next byte pointed at by PC, incrementing PC
    def next_byte
      byte = @memory.get_byte(@registers.pc)
      @registers.inc_pc
      byte
    end

    # Read and return next word pointed at by PC, incrementing PC twice
    def next_word
      word = @memory.get_word(@registers.pc)
      @registers.add_pc(2)
      word
    end

    # Opcode handler methods.

    def op_ld_r_nn(opcode)
      value = next_byte
      r = (opcode >> 3) & 0x07
      if r == 0x06
        # This case is a bit messy, as follows;
        # Non-prefixed: e.g. LD (HL),nn    is 36 nn
        # Prefixed    : e.g. LD (IX+dd),nn is DD 36 dd nn
        reg_sym = @prefix_to_regsym[@prefix]
        if @prefix == Prefix::NONE
          location = @registers.get(reg_sym)
        else
          offset = value
          value = next_byte
          location = (@registers.get(reg_sym) + offset) & 0xFFFF
        end
        @memory.set_byte(location, value)
      else
        # Non-prefixed: e.g. LD H,nn   is 26 nn
        # Prefixed    : e.g. LD IXH,nn is DD 26 nn
        reg_sym = sym_from_r(r)
        @registers.set(reg_sym, value)
      end
    end

    def op_inc_r(opcode)
      r = (opcode >> 3) & 0x07
      if r == 0x06
        reg_sym = @prefix_to_regsym[@prefix]
        d = @prefix == Prefix::NONE ? 0x00 : next_byte
        location = (@registers.get(reg_sym) + d) & 0xFFFF
        value = (@memory.get_byte(location) + 1) & 0xFF
        @memory.set_byte(location, value)
      else
        reg_sym = sym_from_r(r)
        value = @registers.inc(reg_sym)
      end
      update_flags_inc(value)
    end

    def op_dec_r(opcode)
      r = (opcode >> 3) & 0x07
      if r == 0x06
        reg_sym = @prefix_to_regsym[@prefix]
        d = @prefix == Prefix::NONE ? 0x00 : next_byte
        location = (@registers.get(reg_sym) + d) & 0xFFFF
        value = (@memory.get_byte(location) - 1) & 0xFF
        @memory.set_byte(location, value)
      else
        reg_sym = sym_from_r(r)
        value = @registers.dec(reg_sym)
      end
      update_flags_dec(value)
    end

    def op_ret_cc(opcode)
      cc = (opcode >> 3) & 0x07
      return unless condition_from_bitmask(cc)

      value = pop_word
      if value.zero? # Terminate on return or jump to zero address
        @running = false
        return
      end

      @registers.pc = value
    end

    def op_jp_cc(opcode)
      value = next_word
      cc = (opcode >> 3) & 0x07
      return unless condition_from_bitmask(cc)

      if value.zero? # Terminate on return or jump to zero address
        @running = false
        return
      end

      @registers.pc = value
    end

    def op_call_cc(opcode)
      value = next_word
      cc = (opcode >> 3) & 0x07
      return unless condition_from_bitmask(cc)

      push_word(@registers.pc)
      @registers.pc = value
    end

    def op_rst_p(opcode)
      p = (opcode >> 3) & 0x07
      target = p << 3 # eg p == 0x03 -> target == 0x18
      raise "Unimplemented RST #{p.to_2x}" unless target.zero?

      # This is a termination instruction
      @running = false
    end

    def op_ld_dd_nnnn(opcode)
      value = next_word
      dd = (opcode >> 4) & 0x03
      reg_sym = sym_from_register_pair_bitmask_sp(dd)
      @registers.set(reg_sym, value)
    end

    def op_inc_dd(opcode)
      dd = (opcode >> 4) & 0x03
      reg_sym = sym_from_register_pair_bitmask_sp(dd)
      @registers.inc(reg_sym)
    end

    def op_add_hl_ss(opcode)
      dd = (opcode >> 4) & 0x03
      # Use the bitmask to work out the source
      source_sym = sym_from_register_pair_bitmask_sp(dd)
      # Use the current prefix to work out the destination
      dest_sym = @prefix_to_regsym[@prefix]
      value = @registers.get(source_sym)
      hl = @registers.get(dest_sym)
      res = hl + value
      f = @registers.f
      f = (f & (S_MASK | Z_MASK | V_MASK)) |
          (((hl ^ res ^ value) >> 8) & H_MASK) |
          ((res >> 16) & C_MASK) |
          ((res >> 8) & (Y_MASK | X_MASK))
      @registers.f = f
      @registers.set(dest_sym, res & 0xFFFF)
    end

    def op_dec_dd(opcode)
      dd = (opcode >> 4) & 0x03
      reg_sym = sym_from_register_pair_bitmask_sp(dd)
      @registers.dec(reg_sym)
    end

    def op_pop_qq(opcode)
      qq = (opcode >> 4) & 0x03
      reg_sym = sym_from_register_pair_bitmask_af(qq)
      @registers.set(reg_sym, pop_word)
    end

    def op_push_qq(opcode)
      qq = (opcode >> 4) & 0x03
      reg_sym = sym_from_register_pair_bitmask_af(qq)
      push_word(@registers.get(reg_sym))
    end

    def op_nop
      nil
    end

    def op_ld_bci_a
      @memory.set_byte(@registers.bc, @registers.a)
    end

    def op_rlca
      a = @registers.a
      a = (a << 1) | (a >> 7)
      f = (@registers.f & (S_MASK | Z_MASK | V_MASK)) | (a & (Y_MASK | X_MASK | C_MASK))
      @registers.af = ((a & 0xFF) << 8) | f
    end

    def op_exafaf
      @registers.exchange_af
    end

    def op_ld_a_bc
      @registers.a = @memory.get_byte(@registers.bc)
    end

    def op_rrca
      a = @registers.a
      f = (@registers.f & (S_MASK | Z_MASK | V_MASK)) | (a & C_MASK)
      a = (a >> 1) | (a << 7)
      f |= a & (Y_MASK | X_MASK)
      @registers.af = ((a & 0xFF) << 8) | f
    end

    def op_djnz
      offset = next_byte
      b = @registers.b - 1
      @registers.b = b & 0xFF
      @registers.add_pc(offset.twos_byte) unless b.zero?
    end

    def op_ld_dei_a
      @memory.set_byte(@registers.de, @registers.a)
    end

    def op_rla
      a = @registers.a
      f = @registers.f
      carry = (f & C_MASK).zero? ? 0 : 1
      res = ((a << 1) | carry) & 0xFF
      c = (a & 0x80).zero? ? 0 : C_MASK
      f = (f & (S_MASK | Z_MASK | V_MASK)) | c | (res & (Y_MASK | X_MASK))
      @registers.af = (res << 8) | f
    end

    def op_jr
      offset = next_byte
      @registers.add_pc(offset.twos_byte)
    end

    def op_ld_a_de
      @registers.a = @memory.get_byte(@registers.de)
    end

    def op_rra
      a = @registers.a
      f = @registers.f
      res = ((a >> 1) | (f << 7)) & 0xFF
      c = a.odd? ? 1 : 0
      f = (f & (S_MASK | Z_MASK | V_MASK)) | c | (res & (Y_MASK | X_MASK))
      @registers.af = (res << 8) | f
    end

    def op_jr_nz
      offset = next_byte
      @registers.add_pc(offset.twos_byte) unless @registers.test?(:z)
    end

    def op_ld_nnnn_hl
      location = next_word
      sym = @prefix_to_regsym[@prefix]
      value = @registers.get(sym)
      @memory.set_word(location, value)
    end

    def op_daa
      a = @registers.a
      tmp_a = a
      f = @registers.f
      flag_h = @registers.test?(:h)
      flag_c = @registers.af.odd?
      flag_n = @registers.test?(:n)
      if flag_n
        tmp_a = (tmp_a - 0x06) & 0xFF if flag_h || ((a & 0x0F) > 9)
        tmp_a = (tmp_a - 0x60) & 0xFF if flag_c || (a > 0x99)
      else
        tmp_a = (tmp_a + 0x06) & 0xFF if flag_h | ((a & 0x0F) > 9)
        tmp_a = (tmp_a + 0x60) & 0xFF if flag_c | (a > 0x99)
      end
      f = (f & (C_MASK | N_MASK)) | (a > 0x99 ? 1 : 0) | ((a ^ tmp_a) & H_MASK) | @tables.szp[tmp_a]
      @registers.af = (tmp_a << 8) | f
    end

    def op_jr_z
      offset = next_byte
      @registers.add_pc(offset.twos_byte) if @registers.test?(:z)
    end

    def op_ld_hl_nnnni
      location = next_word
      value = @memory.get_word(location)
      sym = @prefix_to_regsym[@prefix]
      @registers.set(sym, value)
    end

    def op_cpl
      a = @registers.a
      f = @registers.f
      a = (~a) & 0xFF
      f = (f & (S_MASK | Z_MASK | V_MASK | C_MASK)) | H_MASK | N_MASK | (a & (Y_MASK | X_MASK))
      @registers.af = (a << 8) | f
    end

    def op_jr_nc
      offset = next_byte
      @registers.add_pc(offset.twos_byte) unless @registers.af.odd?
    end

    def op_ld_nnnn_a
      location = next_word
      @memory.set_byte(location, @registers.a)
    end

    def op_scf
      # Note that I've seen different implementations of this with regards to how
      # the X & Y flags are set. The comments in MAME's z80 implementation seem to
      # imply that they've got it right so I'll use their approach.
      @registers.f = (@registers.f & (S_MASK | Z_MASK | Y_MASK | X_MASK | V_MASK)) |
                     C_MASK |
                     (@registers.a & (Y_MASK | X_MASK))
    end

    def op_jr_c
      offset = next_byte
      @registers.add_pc(offset.twos_byte) if @registers.af.odd?
    end

    def op_ld_a_nnnni
      location = next_word
      @registers.a = @memory.get_byte(location)
    end

    def op_ccf
      # Note that I've seen different implementations of this with regards to how
      # the X & Y flags are set. The comments in MAME's z80 implementation seem to
      # imply that they've got it right so I'll use their approach.
      @registers.f = (@registers.f & (S_MASK | Z_MASK | Y_MASK | X_MASK | V_MASK | C_MASK)) |
                     ((@registers.f & C_MASK) << 4) |
                     (@registers.a & (Y_MASK | X_MASK)) ^ C_MASK
    end

    def op_add_a_r(opcode)
      r = opcode & 0x07
      value = get_register_value_via_bitmask(r)
      reg_add(value)
    end

    def op_adc_a_r(opcode)
      r = opcode & 0x07
      value = get_register_value_via_bitmask(r)
      reg_adc(value)
    end

    def op_sub_r(opcode)
      r = opcode & 0x07
      value = get_register_value_via_bitmask(r)
      reg_sub(value)
    end

    def op_sbc_r(opcode)
      r = opcode & 0x07
      value = get_register_value_via_bitmask(r)
      reg_sbc(value)
    end

    def op_and_r(opcode)
      r = opcode & 0x07
      value = get_register_value_via_bitmask(r)
      reg_and(value)
    end

    def op_xor_r(opcode)
      r = opcode & 0x07
      value = get_register_value_via_bitmask(r)
      reg_xor(value)
    end

    def op_or_r(opcode)
      r = opcode & 0x07
      value = get_register_value_via_bitmask(r)
      reg_or(value)
    end

    def op_cp_r(opcode)
      r = opcode & 0x07
      value = get_register_value_via_bitmask(r)
      reg_cp(value)
    end

    def op_halt
      @running = false
    end

    def op_jp_nnnn
      @registers.pc = next_word
    end

    def op_add_a_nn
      reg_add(next_byte)
    end

    def op_ret
      if (@registers.pc == 0x0006) && @cpm_stub
        # Intercept a return from a stub BDOS call
        value = pop_word
        # Handle a minimal CP/M call in Ruby instead of properly implementing BDOS/BIOS
        case @registers.c
        when 0x02 # Print the character in E
          print format('%c', @registers.e)
        when 0x09 # Print a $ terminated string
          bytes = []
          offset = 0
          ch = 0
          while ch != 0x24
            ch = @memory.get_byte(@registers.de + offset)
            bytes << ch
            offset += 1
          end
          print bytes.slice(0..-2).pack('C*')
        else
          puts "Unhandled BDOS call #{@registers.c.to_2x}"
        end
        @registers.pc = value
        return
      end

      value = pop_word
      if value.zero? # Terminate on return or jump to zero address
        @running = false
        return
      end

      @registers.pc = value
    end

    # Indirection for CB opcodes
    def op_cb
      if @prefix == Prefix::NONE
        byte2 = next_byte
        bits = byte2 & 0xC0
        return op_cb_bit_b_r(byte2) if bits == 0x40
        return op_cb_res_b_s(byte2) if bits == 0x80
        return op_cb_set_b_s(byte2) if bits == 0xC0

        bits = byte2 & 0xF8
        return op_cb_rlc_r(byte2) if bits.zero?
        return op_cb_rrc_r(byte2) if bits == 0x08
        return op_cb_rl_r(byte2) if bits == 0x10
        return op_cb_rr_r(byte2) if bits == 0x18
        return op_cb_sla_r(byte2) if bits == 0x20
        return op_cb_sra_r(byte2) if bits == 0x28
        return op_cb_sll_r(byte2) if bits == 0x30
        return op_cb_srl_r(byte2) if bits == 0x38

        raise "Unhandled CB combination (CB #{byte2.to_2x}), TODO!"
      else
        byte3 = next_byte
        byte4 = next_byte
        r1 = (byte4 >> 3) & 0x07

        bits = byte4 & 0xC7
        return op_cb_set_b_ixy(byte3, r1) if bits == 0xC6
        return op_cb_res_b_ixy(byte3, r1) if bits == 0x86

        bits = byte4 & 0xC0
        return op_cb_bit_b_ixy(byte3, r1) if bits == 0x40

        r2 = byte4 & 0x07
        if r2 == 0x06
          return op_cb_rlc_ixy_d(byte3) if r1.zero?
          return op_cb_rrc_ixy_d(byte3) if r1 == 0x01
          return op_cb_rl_ixy_d(byte3) if r1 == 0x02
          return op_cb_rr_ixy_d(byte3) if r1 == 0x03
          return op_cb_sla_ixy_d(byte3) if r1 == 0x04
          return op_cb_sra_ixy_d(byte3) if r1 == 0x05
          return op_cb_sll_ixy_d(byte3) if r1 == 0x06
          return op_cb_srl_ixy_d(byte3) if r1 == 0x07
        end

        raise "Unhandled #{@prefix.to_2x} CB combination (#{@prefix.to_2x} CB #{byte3.to_2x} #{byte4.to_2x}), TODO!"
      end
    end

    def op_cb_res_b_s(byte2)
      r = byte2 & 0x07
      b = (byte2 >> 3) & 0x07
      if r == 0x06
        mem = @memory.get_byte(@registers.hl)
        mem &= ~(1 << b)
        @memory.set_byte(@registers.hl, mem & 0xFF)
      else
        reg_sym = @sym_from_register_bitmask_r[r]
        data = @registers.get(reg_sym)
        data &= ~(1 << b)
        @registers.set(reg_sym, data)
      end
    end

    def op_cb_set_b_s(byte2)
      r = byte2 & 0x07
      b = (byte2 >> 3) & 0x07
      if r == 0x06
        mem = @memory.get_byte(@registers.hl)
        mem |= (1 << b)
        @memory.set_byte(@registers.hl, mem & 0xFF)
      else
        reg_sym = @sym_from_register_bitmask_r[r]
        data = @registers.get(reg_sym)
        data |= (1 << b)
        @registers.set(reg_sym, data)
      end
    end

    def op_cb_bit_b_r(byte2)
      r = byte2 & 0x07
      b = (byte2 >> 3) & 0x07
      value1 = get_register_value_via_bitmask(r)
      value2 = r == 0x06 ? @registers.hl : value1

      @registers.f = (@registers.f & C_MASK) |
                     H_MASK |
                     (@tables.sz_bit[value1 & (1 << b)] & ~(Y_MASK | X_MASK)) |
                     (value2 & (Y_MASK | X_MASK))
    end

    def op_cb_rlc_r(byte2)
      r = byte2 & 0x07
      if r == 0x06
        value = @memory.get_byte(@registers.hl)
        value = reg_rlc(value)
        @memory.set_byte(@registers.hl, value)
      else
        sym = @sym_from_register_bitmask_r[r]
        value = @registers.get(sym)
        value = reg_rlc(value)
        @registers.set(sym, value)
      end
    end

    def op_cb_rrc_r(byte2)
      r = byte2 & 0x07
      if r == 0x06
        value = @memory.get_byte(@registers.hl)
        value = reg_rrc(value)
        @memory.set_byte(@registers.hl, value)
      else
        sym = @sym_from_register_bitmask_r[r]
        value = @registers.get(sym)
        value = reg_rrc(value)
        @registers.set(sym, value)
      end
    end

    def op_cb_rl_r(byte2)
      r = byte2 & 0x07
      if r == 0x06
        value = @memory.get_byte(@registers.hl)
        value = reg_rl(value)
        @memory.set_byte(@registers.hl, value)
      else
        sym = @sym_from_register_bitmask_r[r]
        value = @registers.get(sym)
        value = reg_rl(value)
        @registers.set(sym, value)
      end
    end

    def op_cb_rr_r(byte2)
      r = byte2 & 0x07
      if r == 0x06
        value = @memory.get_byte(@registers.hl)
        value = reg_rr(value)
        @memory.set_byte(@registers.hl, value)
      else
        sym = @sym_from_register_bitmask_r[r]
        value = @registers.get(sym)
        value = reg_rr(value)
        @registers.set(sym, value)
      end
    end

    def op_cb_sla_r(byte2)
      r = byte2 & 0x07
      if r == 0x06
        value = @memory.get_byte(@registers.hl)
        value = reg_sla(value)
        @memory.set_byte(@registers.hl, value)
      else
        sym = @sym_from_register_bitmask_r[r]
        value = @registers.get(sym)
        value = reg_sla(value)
        @registers.set(sym, value)
      end
    end

    def op_cb_sra_r(byte2)
      r = byte2 & 0x07
      if r == 0x06
        value = @memory.get_byte(@registers.hl)
        value = reg_sra(value)
        @memory.set_byte(@registers.hl, value)
      else
        sym = @sym_from_register_bitmask_r[r]
        value = @registers.get(sym)
        value = reg_sra(value)
        @registers.set(sym, value)
      end
    end

    def op_cb_sll_r(byte2)
      r = byte2 & 0x07
      if r == 0x06
        value = @memory.get_byte(@registers.hl)
        value = reg_sll(value)
        @memory.set_byte(@registers.hl, value)
      else
        sym = @sym_from_register_bitmask_r[r]
        value = @registers.get(sym)
        value = reg_sll(value)
        @registers.set(sym, value)
      end
    end

    def op_cb_srl_r(byte2)
      r = byte2 & 0x07
      if r == 0x06
        value = @memory.get_byte(@registers.hl)
        value = reg_srl(value)
        @memory.set_byte(@registers.hl, value)
      else
        sym = @sym_from_register_bitmask_r[r]
        value = @registers.get(sym)
        value = reg_srl(value)
        @registers.set(sym, value)
      end
    end

    def op_cb_res_b_ixy(offset, b)
      reg_sym = @prefix_to_regsym[@prefix]
      location = (@registers.get(reg_sym) + offset) & 0xFFFF
      data = @memory.get_byte(location)
      data &= ~(1 << b)
      @memory.set_byte(location, data)
    end

    def op_cb_set_b_ixy(offset, b)
      reg_sym = @prefix_to_regsym[@prefix]
      location = (@registers.get(reg_sym) + offset) & 0xFFFF
      data = @memory.get_byte(location)
      data |= (1 << b)
      @memory.set_byte(location, data)
    end

    def op_cb_bit_b_ixy(offset, b)
      reg_sym = @prefix_to_regsym[@prefix]
      location = (@registers.get(reg_sym) + offset) & 0xFFFF
      value = @memory.get_byte(location)
      @registers.f = (@registers.f & C_MASK) |
                     H_MASK |
                     (@tables.sz_bit[value & (1 << b)] & ~(Y_MASK | X_MASK)) |
                     (location & (Y_MASK | X_MASK))
    end

    def op_cb_rlc_ixy_d(byte3)
      reg_sym = @prefix_to_regsym[@prefix]
      location = (@registers.get(reg_sym) + byte3) & 0xFFFF
      value = @memory.get_byte(location)
      value = reg_rlc(value)
      @memory.set_byte(location, value)
    end

    def op_cb_rrc_ixy_d(byte3)
      reg_sym = @prefix_to_regsym[@prefix]
      location = (@registers.get(reg_sym) + byte3) & 0xFFFF
      value = @memory.get_byte(location)
      value = reg_rrc(value)
      @memory.set_byte(location, value)
    end

    def op_cb_rl_ixy_d(byte3)
      reg_sym = @prefix_to_regsym[@prefix]
      location = (@registers.get(reg_sym) + byte3) & 0xFFFF
      value = @memory.get_byte(location)
      value = reg_rl(value)
      @memory.set_byte(location, value)
    end

    def op_cb_rr_ixy_d(byte3)
      reg_sym = @prefix_to_regsym[@prefix]
      location = (@registers.get(reg_sym) + byte3) & 0xFFFF
      value = @memory.get_byte(location)
      value = reg_rr(value)
      @memory.set_byte(location, value)
    end

    def op_cb_sla_ixy_d(byte3)
      reg_sym = @prefix_to_regsym[@prefix]
      location = (@registers.get(reg_sym) + byte3) & 0xFFFF
      value = @memory.get_byte(location)
      value = reg_sla(value)
      @memory.set_byte(location, value)
    end

    def op_cb_sra_ixy_d(byte3)
      reg_sym = @prefix_to_regsym[@prefix]
      location = (@registers.get(reg_sym) + byte3) & 0xFFFF
      value = @memory.get_byte(location)
      value = reg_sra(value)
      @memory.set_byte(location, value)
    end

    def op_cb_sll_ixy_d(byte3)
      reg_sym = @prefix_to_regsym[@prefix]
      location = (@registers.get(reg_sym) + byte3) & 0xFFFF
      value = @memory.get_byte(location)
      value = reg_sll(value)
      @memory.set_byte(location, value)
    end

    def op_cb_srl_ixy_d(byte3)
      reg_sym = @prefix_to_regsym[@prefix]
      location = (@registers.get(reg_sym) + byte3) & 0xFFFF
      value = @memory.get_byte(location)
      value = reg_srl(value)
      @memory.set_byte(location, value)
    end

    def op_call
      target = next_word
      push_word(@registers.pc)
      @registers.pc = target
    end

    def op_adc_a_nn
      reg_adc(next_byte)
    end

    def op_ld_hl_a
      @memory.set_byte(@registers.hl, @registers.a)
    end

    def op_out_nn_a
      port = next_byte
      @io.out(port, @registers.a)
    end

    def op_sub_nn
      reg_sub(next_byte)
    end

    def op_exx
      @registers.exchange
    end

    def op_in_a_nn
      port = next_byte
      @registers.a = @io.in(port, @registers.a)
    end

    def op_sbc_a_nn
      reg_sbc(next_byte)
    end

    def op_ex_spi_hl
      value = @registers.hl
      @registers.hl = @memory.get_word(@registers.sp)
      @memory.set_word(@registers.sp, value)
    end

    def op_and_nn
      value = next_byte
      a = @registers.a & value
      @registers.af = (a << 8) | (@tables.szp[a] | H_MASK)
    end

    def op_jp_hli
      @registers.pc = @registers.hl
    end

    def op_ex_de_hl
      temp = @registers.de
      @registers.de = @registers.hl
      @registers.hl = temp
    end

    def op_ed
      # Handle the various multi-byte ED opcodes.  Some are done via bitmask (eg
      # the various bit operations), others are just a simple case statement)
      byte2 = next_byte

      bits = byte2 & 0xCF
      return op_ed_adc_hl_rr(byte2) if bits == 0x4A
      return op_ed_sbc_hl_rr(byte2) if bits == 0x42
      return op_ed_ld_nnnn_dd(byte2) if bits == 0x43
      return op_ed_ld_dd_nnnn_i(byte2) if bits == 0x4B

      case byte2
      when 0x44
        op_ed_neg
      when 0x57
        op_ed_ld_a_i
      when 0x5B
        op_ed_ld_de_nnnn_i
      when 0x67
        op_ed_rrd
      when 0x6F
        op_ed_rld
      when 0x73
        op_ed_ld_nnnn_sp
      when 0x7B
        op_ed_ld_sp_nnnn
      when 0xA0
        op_ed_ldi
      when 0xA1
        op_ed_cpi
      when 0xA8
        op_ed_ldd
      when 0xA9
        op_ed_cpd
      when 0xB0
        op_ed_ldir
      when 0xB1
        op_ed_cpir
      when 0xB8
        op_ed_lddr
      when 0xB9
        op_ed_cpdr
      else
        raise "Unhandled ED combination (ED #{format('%02X', byte2)})"
      end
    end

    def op_ed_adc_hl_rr(byte2)
      ss = (byte2 >> 4) & 0x03
      sym = sym_from_register_pair_bitmask_sp(ss)
      hl = @registers.hl
      other = @registers.get(sym)
      carry = @registers.carry
      res = hl + other + carry

      f = (((hl ^ res ^ other) >> 8) & H_MASK) |
          ((res >> 16) & C_MASK) |
          ((res >> 8) & (S_MASK | Y_MASK | X_MASK)) |
          ((res & 0xFFFF).zero? ? Z_MASK : 0) |
          (((other ^ hl ^ 0x8000) & (other ^ res) & 0x8000) >> 13)
      @registers.f = f
      @registers.hl = res & 0xFFFF
    end

    def op_ed_sbc_hl_rr(byte2)
      ss = (byte2 >> 4) & 0x03
      sym = sym_from_register_pair_bitmask_sp(ss)
      hl = @registers.hl
      other = @registers.get(sym)
      carry = @registers.carry
      res = hl - other - carry

      f = (((hl ^ res ^ other) >> 8) & H_MASK) |
          N_MASK |
          ((res >> 16) & C_MASK) |
          ((res >> 8) & (S_MASK | Y_MASK | X_MASK)) |
          ((res & 0xFFFF).zero? ? Z_MASK : 0) |
          (((other ^ hl) & (hl ^ res) & 0x8000) >> 13)
      @registers.f = f
      @registers.hl = res & 0xFFFF
    end

    def op_ed_ld_nnnn_dd(byte2)
      dd = (byte2 >> 4) & 0x03
      sym = sym_from_register_pair_bitmask_sp(dd)
      location = next_word
      @memory.set_word(location, @registers.get(sym))
    end

    def op_ed_ld_dd_nnnn_i(byte2)
      dd = (byte2 >> 4) & 0x03
      sym = sym_from_register_pair_bitmask_sp(dd)
      location = next_word
      @registers.set(sym, @memory.get_word(location))
    end

    def op_ed_neg
      value = @registers.a
      @registers.a = 0
      reg_sub(value)
    end

    def op_ed_ld_a_i
      @registers.a = @registers.i
    end

    def op_ed_ld_de_nnnn_i
      location = next_word
      @registers.de = @memory.get_word(location)
    end

    def op_ed_rrd
      a = @registers.a
      f = @registers.f
      hl = @registers.hl
      value = @memory.get_byte(hl)
      @memory.set_byte(hl, (a << 4) | (value >> 4))
      a = (a & 0xF0) | (value & 0x0F)
      @registers.a = a
      @registers.f = (f & C_MASK) | @tables.szp[a]
    end

    def op_ed_rld
      a = @registers.a
      f = @registers.f
      hl = @registers.hl
      value = @memory.get_byte(hl)
      @memory.set_byte(hl, (value << 4) | (a & 0x0F))
      a = (a & 0xF0) | (value >> 4)
      @registers.a = a
      @registers.f = (f & C_MASK) | @tables.szp[a]
    end

    def op_ed_ld_nnnn_sp
      location = next_word
      @memory.set_word(location, @registers.sp)
    end

    def op_ed_ld_sp_nnnn
      location = next_word
      @registers.sp = @memory.get_word(location)
    end

    def op_ed_ldi
      reg_ldblock_single
      @registers.inc(:de)
      @registers.inc(:hl)
    end

    def op_ed_cpi
      reg_cpblock_single
      @registers.inc(:hl)
    end

    def op_ed_ldd
      reg_ldblock_single
      @registers.dec(:de)
      @registers.dec(:hl)
    end

    def op_ed_cpd
      reg_cpblock_single
      @registers.dec(:hl)
    end

    def op_ed_ldir
      loop do
        reg_ldblock_single
        @registers.inc(:de)
        @registers.inc(:hl)
        return if @registers.bc.zero?
      end
    end

    def op_ed_cpir
      loop do
        reg_cpblock_single
        @registers.inc(:hl)
        return if @registers.bc.zero? || @registers.test?(:z)
      end
    end

    def op_ed_lddr
      loop do
        reg_ldblock_single
        @registers.dec(:de)
        @registers.dec(:hl)
        return if @registers.bc.zero?
      end
    end

    def op_ed_cpdr
      loop do
        reg_cpblock_single
        @registers.dec(:hl)
        return if @registers.bc.zero? || @registers.test?(:z)
      end
    end

    def op_xor_n
      value = next_byte
      a = @registers.a ^ value
      @registers.af = (a << 8) | @tables.szp[a]
    end

    def op_di
      # TODO!
    end

    def op_or_nn
      nn = next_byte
      a = @registers.a | nn
      @registers.af = (a << 8) | @tables.szp[a]
    end

    def op_ld_sp_hl
      @registers.sp = @registers.hl
    end

    def op_ei
      # TODO!
    end

    def op_cp_nn
      nn = next_byte
      a = @registers.a
      res = (a - nn) & 0xFF
      @registers.f = @tables.szhvc_sub[(a << 8) | res] & ~(Y_MASK | X_MASK) | (nn & (Y_MASK | X_MASK))
    end

    def op_ld_r1_r2(opcode)
      return op_halt if opcode == 0x76 # the HALT opcode is in the ld r1,r2 range

      r1 = (opcode >> 3) & 0x07
      r2 = opcode & 0x07

      # Handle the various special-cases for this instruction.
      # See page 24 of 'undocumented Z80'
      if @prefix == Prefix::NONE
        # ld r,r'
        if r1 == 0x06
          # ld (hl),r2
          reg2 = @sym_from_register_bitmask_r[r2]
          @memory.set_byte(@registers.hl, @registers.get(reg2))
        elsif r2 == 0x06
          # ld r1,(hl)
          reg1 = @sym_from_register_bitmask_r[r1]
          @registers.set(reg1, @memory.get_byte(@registers.hl))
        else
          # normal
          reg1 = @sym_from_register_bitmask_r[r1]
          reg2 = @sym_from_register_bitmask_r[r2]
          @registers.set(reg1, @registers.get(reg2))
        end
      elsif r1 == 0x06
        # prefix is either DD or FD, indexed register access
        # ld (ix+d),r2 or ld (iy+d),r2
        offset = next_byte
        reg1 = @prefix_to_regsym[@prefix]
        value2 = get_register_value_via_bitmask(r2, ignore_prefix: true)
        location = (@registers.get(reg1) + offset) & 0xFFFF
        @memory.set_byte(location, value2)
      elsif r2 == 0x06
        # prefix is either DD or FD, indexed register access
        # ld r1,(ix+d) or ld r1,(iy+d)
        offset = next_byte
        reg1 = @sym_from_register_bitmask_r[r1]
        reg2 = @prefix_to_regsym[@prefix]
        location = (@registers.get(reg2) + offset) & 0xFFFF
        @registers.set(reg1, @memory.get_byte(location))
      else
        # prefix is either DD or FD, direct (not indexed) register access
        value2 = get_register_value_via_bitmask(r2)
        prefixed_set_register_via_bitmask(r1, value2)
      end
    end

    # Opcode helper methods

    # Push the supplied 16-bit word onto the stack (stack grows downwards)
    def push_word(value)
      new_sp = @registers.dec_dec_sp
      @memory.set_word(new_sp, value)
    end

    # Return the top 16-bit word from the stack (stack grows downwards)
    def pop_word
      new_sp = @registers.inc_inc_sp
      @memory.get_word(new_sp - 2)
    end

    # Helper for 8-bit INC opcodes
    def update_flags_inc(value)
      @registers.f = (@registers.f & 0x01) | @tables.szhv_inc[value]
    end

    # Helper for 8-bit DEC opcodes
    def update_flags_dec(value)
      @registers.f = (@registers.f & 0x01) | @tables.szhv_dec[value]
    end

    # Helper for 8-bit AND opcodes
    def reg_and(value)
      a = @registers.a & value
      @registers.af = (a << 8) | (@tables.szp[a] | H_MASK)
    end

    # Helper for 8-bit OR opcodes
    def reg_or(value)
      a = @registers.a | value
      @registers.af = (a << 8) | @tables.szp[a]
    end

    # Helper for 8-bit XOR opcodes
    def reg_xor(value)
      a = @registers.a ^ value
      @registers.af = (a << 8) | @tables.szp[a]
    end

    # Helper for 8-bit CP opcodes
    def reg_cp(value)
      a = @registers.a
      res = (a - value) & 0xFF
      @registers.f = (@tables.szhvc_sub[(a << 8) | res] & ~(Y_MASK | X_MASK)) | (value & (Y_MASK | X_MASK))
    end

    # Helper for 8-bit ADD opcodes
    def reg_add(value)
      ah = @registers.af & 0xFF00
      res = ((ah >> 8) + value) & 0xFF
      @registers.af = (res << 8) | @tables.szhvc_add[ah | res]
    end

    # Helper for 8-bit SUB opcodes
    def reg_sub(value)
      ah = @registers.af & 0xFF00
      res = ((ah >> 8) - value) & 0xFF
      @registers.af = (res << 8) | @tables.szhvc_sub[ah | res]
    end

    # Helper for 8-bit ADC opcodes
    def reg_adc(value)
      ah = @registers.af & 0xFF00
      carry = @registers.carry
      res = ((ah >> 8) + value + carry) & 0xFF
      f = @tables.szhvc_add[(carry << 16) | ah | res]
      @registers.af = (res << 8) | f
    end

    # Helper for 8-bit SBC opcodes
    def reg_sbc(value)
      ah = @registers.af & 0xFF00
      carry = @registers.carry
      res = ((ah >> 8) - value - carry) & 0xFF
      f = @tables.szhvc_sub[(carry << 16) | ah | res]
      @registers.af = (res << 8) | f
    end

    # Building block for CPI, CPIR, CPD, CPDR
    def reg_cpblock_single
      value = @memory.get_byte(@registers.hl)
      a = @registers.a
      res = (a - value) & 0xFF
      @registers.dec(:bc)
      f = @registers.f
      f = (f & C_MASK) | (@tables.sz[res] & ~(X_MASK | Y_MASK)) | ((a ^ value ^ res) & H_MASK) | N_MASK
      res -= 1 unless (f & H_MASK).zero?
      f |= Y_MASK unless (res & 0x02).zero?
      f |= X_MASK unless (res & 0x08).zero?
      f |= V_MASK unless @registers.bc.zero?
      @registers.f = f
    end

    # Building block for LDI, LDIR, LDD, LDIR
    def reg_ldblock_single
      value = @memory.get_byte(@registers.hl)
      @memory.set_byte(@registers.de, value)

      f = @registers.f & (S_MASK | Z_MASK | C_MASK)
      a = @registers.a
      f |= Y_MASK unless ((a + value) & 0x02).zero?
      f |= X_MASK unless ((a + value) & 0x08).zero?
      @registers.dec(:bc)
      f |= V_MASK unless @registers.bc.zero?
      @registers.f = f
    end

    # Building block for RLC etc
    def reg_rlc(value)
      c = (value & 0x80).zero? ? 0 : C_MASK
      value = ((value << 1) | (value >> 7)) & 0xFF
      @registers.f = @tables.szp[value] | c
      value
    end

    # Building block for RRC etc
    def reg_rrc(value)
      c = value.odd? ? C_MASK : 0
      value = ((value >> 1) | (value << 7)) & 0xFF
      @registers.f = @tables.szp[value] | c
      value
    end

    # Building block for RL etc
    def reg_rl(value)
      c = (value & 0x80).zero? ? 0 : C_MASK
      value = ((value << 1) | (@registers.f & C_MASK)) & 0xFF
      @registers.f = @tables.szp[value] | c
      value
    end

    # Building block for RR etc
    def reg_rr(value)
      c = value.odd? ? C_MASK : 0
      value = ((value >> 1) | (@registers.f << 7)) & 0xFF
      @registers.f = @tables.szp[value] | c
      value
    end

    # Building block for SLA etc
    def reg_sla(value)
      c = (value & 0x80).zero? ? 0 : C_MASK
      value = (value << 1) & 0xFF
      @registers.f = @tables.szp[value] | c
      value
    end

    # Building block for SRA etc
    def reg_sra(value)
      c = value.odd? ? C_MASK : 0
      value = ((value >> 1) | (value & 0x80)) & 0xFF
      @registers.f = @tables.szp[value] | c
      value
    end

    # Building block for SLL etc
    def reg_sll(value)
      c = (value & 0x80).zero? ? 0 : C_MASK
      value = ((value << 1) | 0x01) & 0xFF
      @registers.f = @tables.szp[value] | c
      value
    end

    # Building block for SRL etc
    def reg_srl(value)
      c = value.odd? ? C_MASK : 0
      value = (value >> 1) & 0xFF
      @registers.f = @tables.szp[value] | c
      value
    end

    # Return the value in a byte register based on a 3-bit bitmask.
    # Used by (eg) "sub r" where r is a bitmask indicating the source register
    def get_register_value_via_bitmask(bitmask, ignore_prefix: false)
      prefix = ignore_prefix ? 0 : @prefix
      case bitmask
      when 0x00 then @registers.b
      when 0x01 then @registers.c
      when 0x02 then @registers.d
      when 0x03 then @registers.e
      when 0x04
        case prefix
        when Prefix::NONE then @registers.h
        when Prefix::DD then @registers.ixh
        when Prefix::FD then @registers.iyh
        else
          raise 'Logic error'
        end
      when 0x05
        case prefix
        when Prefix::NONE then @registers.l
        when Prefix::DD then @registers.ixl
        when Prefix::FD then @registers.iyl
        else
          raise 'Logic error'
        end
      when 0x06
        case prefix
        when Prefix::NONE
          @memory.get_byte(@registers.hl)
        when Prefix::DD
          offset = next_byte
          @memory.get_byte((@registers.ix + offset) & 0xFFFF)
        when Prefix::FD
          offset = next_byte
          @memory.get_byte((@registers.iy + offset) & 0xFFFF)
        end
      when 0x07 then @registers.a
      else
        raise "Log error with bitmask=#{bitmask.to_2x}"
      end
    end

    # Assuming the prefix is currently either DD or FD, set the value
    # of a byte register based on a 3-bit bitmask.
    def prefixed_set_register_via_bitmask(bits, value)
      case bits
      when 0x00 then @registers.b = value
      when 0x01 then @registers.c = value
      when 0x02 then @registers.d = value
      when 0x03 then @registers.e = value
      when 0x04
        case @prefix
        when 0xDD then @registers.ixh = value
        when 0xFD then @registers.iyh = value
        else
          raise 'Logic error'
        end
      when 0x05
        case @prefix
        when 0xDD then @registers.ixl = value
        when 0xFD then @registers.iyl = value
        else
          raise 'Logic error'
        end
      when 0x07 then @registers.a = value
      else
        raise 'Illegal instruction'
      end
    end

    def sym_from_register_pair_bitmask_sp(value)
      case value
      when 0x00 then :bc
      when 0x01 then :de
      when 0x02 then @prefix_to_regsym[@prefix]
      when 0x03 then :sp
      else
        raise 'Illegal register bitmask'
      end
    end

    def sym_from_register_pair_bitmask_af(value)
      case value
      when 0x00 then :bc
      when 0x01 then :de
      when 0x02 then @prefix_to_regsym[@prefix]
      when 0x03 then :af
      else
        raise 'Illegal register bitmask'
      end
    end

    # Used in (eg) ret_cc (value is the 3 bit CC condition)
    # Returns a bool "condition met?" indication
    def condition_from_bitmask(value)
      case value
      when 0x00 then (@registers.af & Z_MASK).zero?
      when 0x01 then (@registers.af & Z_MASK).positive?
      when 0x02 then @registers.af.even? # Small optimisation for performance
      when 0x03 then @registers.af.odd? # Small optimisation for performance
      when 0x04 then (@registers.af & V_MASK).zero?
      when 0x05 then (@registers.af & V_MASK).positive?
      when 0x06 then (@registers.af & S_MASK).zero?
      when 0x07 then (@registers.af & S_MASK).positive?
      else
        raise 'Logic error'
      end
    end

    # Refer to table 8.4 of Undocumented Z80
    def sym_from_r(r)
      @sym_from_register_bitmask[@prefix][r]
    end
  end
end
