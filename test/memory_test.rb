# frozen_string_literal: true

require 'minitest/autorun'

require 'test_helper'

class MemoryTest < Minitest::Test
  def setup
    @memory = R80::Memory.new(65_536)
  end

  def teardown
    # Do nothing
  end

  def test_size
    # Verify that the requested size is the same as the reported size
    assert_equal(65_536, @memory.size)
  end

  def test_bulk_set_get
    # Load a particular byte pattern to emulated RAM at address 0100 onwards
    pattern = 'abcdefghijk'
    @memory[0x0100, pattern.size] = pattern

    # Read back a subset of it
    pattern2 = @memory[0x0101, 5]
    assert('bcdef', pattern2)
  end

  def test_set_get
    # Set by byte, read back by bytes and words
    @memory.set_byte(0x1000, 0x12)
    @memory.set_byte(0x1001, 0x34)
    assert_equal(0x12, @memory.get_byte(0x1000))
    assert_equal(0x34, @memory.get_byte(0x1001))
    assert_equal(0x3412, @memory.get_word(0x1000))

    # Set by word, read back by bytes and words
    @memory.set_word(0x1000, 0xabcd)
    assert_equal(0xabcd, @memory.get_word(0x1000))
    assert_equal(0xcd, @memory.get_byte(0x1000))
    assert_equal(0xab, @memory.get_byte(0x1001))
  end

  def test_dump
    # We don't check the exact details of the dump output, just
    # that it looks to be of plausible size and it hasn't caused
    # an exception to be thrown
    s = @memory.dump_to_string(0x0100, 64)
    line_count = s.split("\n").size
    assert_equal(4, line_count)
  end
end
