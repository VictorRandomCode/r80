# R80

This gem implements a pure-Ruby Z80 core with no significant external dependencies. Being pure Ruby
performance will be much slower than a compiled equivalent, but the upside is that it is very easy
to include in any arbitrary Ruby project. The Z80 core is fairly complete and includes all
'undocumented' Z80 instructions and flags as documented in http://z80.info/zip/z80-documented.pdf
and it successfully (eventually!) runs `ZEXALL.COM`

The implementation of the core is originally from scratch but quite a bit of the flag handling and
flag lookup tables is based on the MAME Z80 core at
https://github.com/mamedev/mame/tree/master/src/devices/cpu/z80

This core does not yet support interrupts, that's a future feature.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'r80'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install r80

## Usage

A good starting point is to look at `bin/runner.rb`

## Development

To install this gem onto your local machine, run `bundle exec rake install`. To release a new
version, update the version number in `version.rb`, and then run `bundle exec rake release`, which
will create a git tag for the version, push git commits and the created tag, and push the `.gem`
file to [rubygems.org](https://rubygems.org).

## Compatibility

This is expected to work identically across any platform supporting Ruby 2.7 or greater.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/VictorRandomCode/r80.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
