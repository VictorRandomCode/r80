# frozen_string_literal: true

module R80
  C_MASK = 1 << 0
  N_MASK = 1 << 1
  V_MASK = 1 << 2
  X_MASK = 1 << 3
  H_MASK = 1 << 4
  Y_MASK = 1 << 5
  Z_MASK = 1 << 6
  S_MASK = 1 << 7
end

# Helpers to simplify consistent numeric output
class Integer
  def to_2x
    format '%02X', self
  end

  def to_4x
    format '%04X', self
  end

  # Given a value 0..255, return the two's complement
  def twos_byte
    self >= 0x80 ? self - 0x100 : self
  end
end
