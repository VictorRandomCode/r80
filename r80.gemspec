# frozen_string_literal: true

require_relative 'lib/r80/version'

Gem::Specification.new do |spec|
  spec.name          = 'r80'
  spec.version       = R80::VERSION
  spec.authors       = ['Victor Wodecki']
  spec.email         = ['vwodecki@gmail.com']

  spec.summary       = 'A pure-Ruby Z80 emulator core.'
  spec.homepage      = 'https://github.com/VictorRandomCode/r80'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 2.7.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/VictorRandomCode/zcpm'
  spec.metadata['changelog_uri'] = 'https://github.com/VictorRandomCode/zcpm/CHANGELOG.md'
  spec.metadata['rubygems_mfa_required'] = 'true'

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:test|spec|features)/|\.(?:git|travis|circleci)|appveyor)})
    end
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # For more information and examples about making a new gem, checkout our
  # guide at: https://bundler.io/guides/creating_gem.html
end
