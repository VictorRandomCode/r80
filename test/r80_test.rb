# frozen_string_literal: true

require 'test_helper'

class R80Test < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::R80::VERSION
  end
end
