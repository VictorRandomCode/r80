# frozen_string_literal: true

require_relative 'r80/io'
require_relative 'r80/memory'
require_relative 'r80/numbers'
require_relative 'r80/registers'
require_relative 'r80/system'
require_relative 'r80/tables'
require_relative 'r80/version'

module R80
  class Error < StandardError; end
end
