# frozen_string_literal: true

require 'minitest/autorun'

require 'test_helper'

class RegistersTest < Minitest::Test
  def setup
    @registers = R80::Registers.new(0x0100)
  end

  def teardown
    # Do nothing
  end

  def test_flags
    # Set all flags to true and verify
    @registers.f = 0xFF
    assert(@registers.test?(:s))
    assert(@registers.test?(:z))
    assert(@registers.test?(:y))
    assert(@registers.test?(:h))
    assert(@registers.test?(:x))
    assert(@registers.test?(:p))
    assert(@registers.test?(:n))
    assert(@registers.test?(:c))
    # Reset all flags and verify
    @registers.f = 0x00
    assert(!@registers.test?(:s))
    assert(!@registers.test?(:z))
    assert(!@registers.test?(:y))
    assert(!@registers.test?(:h))
    assert(!@registers.test?(:x))
    assert(!@registers.test?(:p))
    assert(!@registers.test?(:n))
    assert(!@registers.test?(:c))
    # Set just Z and C
    @registers.f = R80::Z_MASK | R80::C_MASK
    assert(!@registers.test?(:s))
    assert(@registers.test?(:z))
    assert(!@registers.test?(:y))
    assert(!@registers.test?(:h))
    assert(!@registers.test?(:x))
    assert(!@registers.test?(:p))
    assert(!@registers.test?(:n))
    assert(@registers.test?(:c))
  end

  # Show that setting registers either as 16-bit value or 8-bit H/L values works as it should
  def test_high_low
    @registers.af = 0x1234
    assert_equal(0x12, @registers.a)
    assert_equal(0x34, @registers.f)
    @registers.f = 0x53
    assert_equal(0x1253, @registers.af)

    @registers.h = 0x44
    @registers.l = 0x55
    assert_equal(0x4455, @registers.hl)

    @registers.hl = 0xBBAA
    assert_equal(0xBB, @registers.h)
    assert_equal(0xAA, @registers.l)
  end

  # Exercise some basic increments/decrements
  def test_inc_dec_word
    @registers.bc = 0x1000
    @registers.inc(:bc)
    assert_equal(0x1001, @registers.bc)
    @registers.dec(:bc)
    assert_equal(0x1000, @registers.bc)

    # Test 'inc helpers'
    @registers.pc = 0x0200
    @registers.inc_pc
    assert_equal(0x0201, @registers.pc)

    @registers.sp = 0x0300
    @registers.inc_inc_sp
    assert_equal(0x0302, @registers.sp)
  end

  def test_inc_dec_byte
    # Note that Registers.inc (et al) don't change flags, instead that's
    # a concern of code in System. Hence we don't check flags here, but
    # we should do so in the System test code.
    @registers.de = 0x0000
    @registers.inc(:e)
    assert_equal(0x01, @registers.e) # E incremented
    assert_equal(0x00, @registers.d) # D unchanged
    @registers.dec(:e)
    assert_equal(0x00, @registers.e) # E decremented
    assert_equal(0x00, @registers.d) # D unchanged
  end
end
