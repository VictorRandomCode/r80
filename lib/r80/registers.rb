# frozen_string_literal: true

module R80
  # Implementation note. This file was originally implemented in a nicer, more
  # "proper" OO approach, but profiling showed it to be a significant bottleneck.
  # I've since flattened it somewhat and now uses more repetitive inline
  # operations to improve performance.

  # A set of general-purpose registers for a Z80; there is a 'main' and an
  # 'alternate' of these.
  class GeneralPurposeRegisterSet
    attr_accessor :a, :f, :bc, :de, :hl

    def initialize
      # AF is normally treated as two 8-bit values, whereas BC/DE/HL are used frequently
      # as either pairs of 8-bit values or single 16-bit values
      @a = 0x00
      @f = 0x00
      @bc = 0x0000
      @de = 0x0000
      @hl = 0x0000
      @flag_bits = { s: 7, z: 6, y: 5, h: 4, x: 3, p: 2, n: 1, c: 0 }
    end

    # Return true if the specified flag symbol is set, false otherwise
    def test?(flag)
      !(@f & (1 << @flag_bits[flag])).zero?
    end

    def af
      (@a << 8) | @f
    end

    def af=(value)
      @a = value >> 8
      @f = value & 0xFF
    end

    def b
      @bc >> 8
    end

    def b=(value)
      @bc = (value << 8) | (@bc & 0xFF)
    end

    def c
      @bc & 0xFF
    end

    def c=(value)
      @bc = (@bc & 0xFF00) | value
    end

    def d
      @de >> 8
    end

    def d=(value)
      @de = (value << 8) | (@de & 0xFF)
    end

    def e
      @de & 0xFF
    end

    def e=(value)
      @de = (@de & 0xFF00) | value
    end

    def h
      @hl >> 8
    end

    def h=(value)
      @hl = (value << 8) | (@hl & 0xFF)
    end

    def l
      @hl & 0xFF
    end

    def l=(value)
      @hl = (@hl & 0xFF00) | value
    end
  end

  # A complete set of Z80 registers
  class Registers
    attr_accessor :pc, :sp, :ix, :iy
    attr_reader :alternate

    def initialize(initial_pc)
      @main = GeneralPurposeRegisterSet.new
      @alternate = GeneralPurposeRegisterSet.new
      @pc = initial_pc
      @sp = 0xF800 # TODO: Make this initial value configurable
      @ix = 0x0000
      @iy = 0x0000
      @i = 0
      @r = 0

      # Set values to match what ZCPM uses on startup
      @main.af = 0xFFFF
      @main.bc = 0x00FF
      @main.de = 0x03FF
      @main.hl = 0x0000
    end

    # This implements the 'exx' functionality
    def exchange
      @main.bc, @alternate.bc = @alternate.bc, @main.bc
      @main.de, @alternate.de = @alternate.de, @main.de
      @main.hl, @alternate.hl = @alternate.hl, @main.hl
    end

    # This implements the 'ex af,af"' functionality
    def exchange_af
      @main.af, @alternate.af = @alternate.af, @main.af
    end

    # Note that there's several ways we can implement these concepts in Ruby; the way
    # that I've ended up using seems to be the best one on balance for our use cases

    def af
      @main.af
    end

    def af=(value)
      @main.af = value
    end

    def a
      @main.a
    end

    def a=(value)
      @main.a = value
    end

    def f
      @main.f
    end

    def f=(value)
      @main.f = value
    end

    def bc
      @main.bc
    end

    def bc=(value)
      @main.bc = value
    end

    def b
      @main.b
    end

    def b=(value)
      @main.b = value
    end

    def c
      @main.c
    end

    def c=(value)
      @main.c = value
    end

    def de
      @main.de
    end

    def de=(value)
      @main.de = value
    end

    def d
      @main.d
    end

    def d=(value)
      @main.d = value
    end

    def e
      @main.e
    end

    def e=(value)
      @main.e = value
    end

    def hl
      @main.hl
    end

    def hl=(value)
      @main.hl = value
    end

    def h
      @main.h
    end

    def h=(value)
      @main.h = value
    end

    def l
      @main.l
    end

    def l=(value)
      @main.l = value
    end

    def ixh
      @ix >> 8
    end

    def ixl
      @ix & 0xFF
    end

    def ixh=(value)
      @ix = (value << 8) | (@ix & 0xFF)
    end

    def ixl=(value)
      @ix = (@ix & 0xFF00) | value
    end

    def iyh
      @iy >> 8
    end

    def iyl
      @iy & 0xFF
    end

    def iyh=(value)
      @iy = (value << 8) | (@iy & 0xFF)
    end

    def iyl=(value)
      @iy = (@iy & 0xFF00) | value
    end

    # Increment and return the specified register. Flags are not affected.
    def inc(register)
      case register
      when :a
        @main.a = (@main.a + 1) & 0xFF
      when :bc
        @main.bc = (@main.bc + 1) & 0xFFFF
      when :b
        @main.b = (@main.b + 1) & 0xFF
      when :c
        @main.c = (@main.c + 1) & 0xFF
      when :de
        @main.de = (@main.de + 1) & 0xFFFF
      when :d
        @main.d = (@main.d + 1) & 0xFF
      when :e
        @main.e = (@main.e + 1) & 0xFF
      when :hl
        @main.hl = (@main.hl + 1) & 0xFFFF
      when :h
        @main.h = (@main.h + 1) & 0xFF
      when :l
        @main.l = (@main.l + 1) & 0xFF
      when :pc
        @pc = (@pc + 1) & 0xFFFF
      when :sp
        @sp = (@sp + 1) & 0xFFFF
      when :ix
        @ix = (@ix + 1) & 0xFFFF
      when :ixh
        @ix = (((@ix & 0xFF00) + 0x100) & 0xFF00) | (@ix & 0xFF)
        @ix >> 8
      when :ixl
        @ix = (@ix & 0xFF00) | ((@ix + 1) & 0xFF)
        @ix & 0xFF
      when :iy
        @iy = (@iy + 1) & 0xFFFF
      when :iyh
        @iy = (((@iy & 0xFF00) + 0x100) & 0xFF00) | (@iy & 0xFF)
        @iy >> 8
      when :iyl
        @iy = (@iy & 0xFF00) | ((@iy + 1) & 0xFF)
        @iy & 0xFF
      else
        raise 'Unhandled register increment'
      end
    end

    # Decrement and return the specified register. Flags are not affected.
    def dec(register)
      case register
      when :a
        @main.a = (@main.a - 1) & 0xFF
      when :bc
        @main.bc = (@main.bc - 1) & 0xFFFF
      when :b
        @main.b = (@main.b - 1) & 0xFF
      when :c
        @main.c = (@main.c - 1) & 0xFF
      when :de
        @main.de = (@main.de - 1) & 0xFFFF
      when :d
        @main.d = (@main.d - 1) & 0xFF
      when :e
        @main.e = (@main.e - 1) & 0xFF
      when :hl
        @main.hl = (@main.hl - 1) & 0xFFFF
      when :h
        @main.h = (@main.h - 1) & 0xFF
      when :l
        @main.l = (@main.l - 1) & 0xFF
      when :pc
        @pc = (@pc - 1) & 0xFFFF
      when :sp
        @sp = (@sp - 1) & 0xFFFF
      when :ix
        @ix = (@ix - 1) & 0xFFFF
      when :ixh
        @ix = (((@ix & 0xFF00) - 0x100) & 0xFF00) | (@ix & 0xFF)
        @ix >> 8
      when :ixl
        @ix = (@ix & 0xFF00) | ((@ix - 1) & 0xFF)
        @ix & 0xFF
      when :iy
        @iy = (@iy - 1) & 0xFFFF
      when :iyh
        @iy = (((@iy & 0xFF00) - 0x100) & 0xFF00) | (@iy & 0xFF)
        @iy >> 8
      when :iyl
        @iy = (@iy & 0xFF00) | ((@iy - 1) & 0xFF)
        @iy & 0xFF
      else
        raise 'Unhandled register decrement'
      end
    end

    def set(register, value)
      case register
      when :af then @main.af = value
      when :f then @main.f = value
      when :a then @main.a = value
      when :bc then @main.bc = value
      when :b then @main.b = value
      when :c then @main.c = value
      when :de then @main.de = value
      when :d then @main.d = value
      when :e then @main.e = value
      when :hl then @main.hl = value
      when :h then @main.h = value
      when :l then @main.l = value
      when :pc then @pc = value
      when :sp then @sp = value
      when :ix then @ix = value
      when :ixh then self.ixh = value
      when :ixl then self.ixl = value
      when :iy then @iy = value
      when :iyh then self.iyh = value
      when :iyl then self.iyl = value
      else
        raise "Unhandled register set ('#{register}')"
      end
    end

    def get(register)
      case register
      when :af then @main.af
      when :a then @main.a
      when :f then @main.f
      when :bc then @main.bc
      when :b then @main.b
      when :c then @main.c
      when :de then @main.de
      when :d then @main.d
      when :e then @main.e
      when :hl then @main.hl
      when :h then @main.h
      when :l then @main.l
      when :pc then @main.pc
      when :sp then @sp
      when :ix then @ix
      when :ixh then ixh
      when :ixl then ixl
      when :iy then @iy
      when :iyh then iyh
      when :iyl then iyl
      else
        raise "Unhandled register get ('#{register}')"
      end
    end

    def test?(flag)
      @main.test?(flag)
    end

    # Helper methods to help speed things up a bit
    def inc_pc
      @pc = (@pc + 1) & 0xFFFF
    end

    def add_pc(value)
      @pc = (@pc + value) & 0xFFFF
    end

    def inc_inc_sp
      @sp = (@sp + 2) & 0xFFFF
    end

    def dec_dec_sp
      @sp = (@sp - 2) & 0xFFFF
    end

    # Returns 1 if the carry bit is set, 0 otherwise
    def carry
      @main.af.odd? ? 1 : 0
    end
  end
end
