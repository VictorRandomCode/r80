# frozen_string_literal: true

require_relative 'numbers'

module R80
  # Implement an area of RAM to support a Z80
  class Memory
    attr_reader :size

    # In a memory dump, how many bytes per row
    BYTES_PER_ROW = 16

    def initialize(size)
      @size = size

      # Set up the RAM as a String of bytes
      @ram = 0.chr * size
      @ram.force_encoding 'ASCII-8BIT'
    end

    # The output of this is based on the ZSID 'd' command, returned as
    # a string (which can be sent to stdout or post-processed if needed)
    def dump_to_string(offset, size)
      result = ''
      start = offset & 0xFFF0
      ((size + start - offset) / BYTES_PER_ROW).times do |row|
        line = format(' %04X:', (start + row * BYTES_PER_ROW) & 0xFFFF)
        bytes = ''
        chars = ' '
        BYTES_PER_ROW.times do |col|
          byte = @ram.getbyte((start + row * BYTES_PER_ROW + col) & 0xFFFF)
          bytes += " #{format('%02X', byte)}"
          chars += if (byte >= 32) && (byte < 127)
                     byte.chr
                   else
                     '.'
                   end
        end
        result += line + bytes + chars + "\n"
      end
      result
    end

    def dump(offset, size)
      puts dump_to_string(offset, size)
    end

    def get_byte(address)
      @ram.getbyte(address)
    end

    def set_byte(address, data)
      @ram.setbyte(address, data)
    end

    def get_word(address)
      (@ram.getbyte(address + 1) << 8) | @ram.getbyte(address)
    end

    def set_word(address, data)
      @ram.setbyte(address, data & 0xFF)
      @ram.setbyte(address + 1, (data >> 8) & 0xFF)
    end

    # Used for reading an array of bytes from RAM
    def [](*params)
      raise 'Wrong parameters' if params.size != 2

      count = params.pop
      offset = params.pop
      @ram[offset, count]
    end

    # Used for copying an array of bytes into RAM
    def []=(*params)
      raise 'Wrong parameters' if params.size != 3

      value = params.pop
      count = params.pop
      offset = params.pop
      raise "Mismatched data size (count=#{count}, requested size=#{value.size})" if value.size != count

      @ram[offset, count] = value
    end
  end
end
