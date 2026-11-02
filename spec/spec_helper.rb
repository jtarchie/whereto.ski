# frozen_string_literal: true

require 'webmock/rspec'
require_relative '../lib/follow_the_snow'
require 'json'
require 'rack'

# Capybara configuration for browser testing
require 'capybara/rspec'
require 'selenium-webdriver'

# Allow WebMock to permit connections to localhost for Capybara/Selenium
WebMock.disable_net_connect!(allow_localhost: true)

Capybara.register_driver :headless_chrome do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument('--headless')
  options.add_argument('--no-sandbox')
  options.add_argument('--disable-dev-shm-usage')
  options.add_argument('--disable-gpu')
  options.add_argument('--window-size=1400,900')

  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
end

Capybara.javascript_driver     = :headless_chrome
Capybara.default_driver        = :headless_chrome
Capybara.default_max_wait_time = 5

module SharedBuild
  class << self
    attr_reader :build_dir

    def perform!
      return if @build_dir

      @build_dir = Dir.mktmpdir
      pages_dir  = File.expand_path(File.join(__dir__, '..', 'pages'))
      sqlite     = File.expand_path(File.join(__dir__, '..', 'data', 'features.sqlite'))
      resorts    = FollowTheSnow::Resort.from_sqlite(sqlite)

      builder = FollowTheSnow::Builder::Site.new(
        build_dir: @build_dir,
        resorts: resorts,
        source_dir: pages_dir,
        logger_io: File.open(File::NULL, 'w')
      )
      builder.build!
    end

    def cleanup!
      FileUtils.rm_rf(@build_dir) if @build_dir && File.exist?(@build_dir)
      @build_dir = nil
    end
  end
end

RSpec.configure do |config|
  config.after(:suite) do
    SharedBuild.cleanup!
  end

  # Include Capybara DSL for feature specs
  config.include Capybara::DSL

  # rspec-expectations config goes here. You can use an alternate
  # assertion/expectation library such as wrong or the stdlib/minitest
  # assertions if you prefer.
  config.expect_with :rspec do |expectations|
    # This option will default to `true` in RSpec 4. It makes the `description`
    # and `failure_message` of custom matchers include text for helper methods
    # defined using `chain`, e.g.:
    #     be_bigger_than(2).and_smaller_than(4).description
    #     # => "be bigger than 2 and smaller than 4"
    # ...rather than:
    #     # => "be bigger than 2"
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  # rspec-mocks config goes here. You can use an alternate test double
  # library (such as bogus or mocha) by changing the `mock_with` option here.
  config.mock_with :rspec do |mocks|
    # Prevents you from mocking or stubbing a method that does not exist on
    # a real object. This is generally recommended, and will default to
    # `true` in RSpec 4.
    mocks.verify_partial_doubles = true
  end

  # This option will default to `:apply_to_host_groups` in RSpec 4 (and will
  # have no way to turn it off -- the option exists only for backwards
  # compatibility in RSpec 3). It causes shared context metadata to be
  # inherited by the metadata hash of host groups and examples, rather than
  # triggering implicit auto-inclusion in groups with matching metadata.
  config.shared_context_metadata_behavior = :apply_to_host_groups

  # The settings below are suggested to provide a good initial experience
  # with RSpec, but feel free to customize to your heart's content.
  #   # This allows you to limit a spec run to individual examples or groups
  #   # you care about by tagging them with `:focus` metadata. When nothing
  #   # is tagged with `:focus`, all examples get run. RSpec also provides
  #   # aliases for `it`, `describe`, and `context` that include `:focus`
  #   # metadata: `fit`, `fdescribe` and `fcontext`, respectively.
  #   config.filter_run_when_matching :focus
  #
  #   # Allows RSpec to persist some state between runs in order to support
  #   # the `--only-failures` and `--next-failure` CLI options. We recommend
  #   # you configure your source control system to ignore this file.
  #   config.example_status_persistence_file_path = "spec/examples.txt"
  #
  #   # Limits the available syntax to the non-monkey patched syntax that is
  #   # recommended. For more details, see:
  #   # https://relishapp.com/rspec/rspec-core/docs/configuration/zero-monkey-patching-mode
  #   config.disable_monkey_patching!
  #
  #   # This setting enables warnings. It's recommended, but in some cases may
  #   # be too noisy due to issues in dependencies.
  #   config.warnings = true
  #
  #   # Many RSpec users commonly either run the entire suite or an individual
  #   # file, and it's useful to allow more verbose output when running an
  #   # individual spec file.
  #   if config.files_to_run.one?
  #     # Use the documentation formatter for detailed output,
  #     # unless a formatter has already been configured
  #     # (e.g. via a command-line flag).
  #     config.default_formatter = "doc"
  #   end
  #
  #   # Print the 10 slowest examples and example groups at the
  #   # end of the spec run, to help surface which specs are running
  #   # particularly slow.
  #   config.profile_examples = 10
  #
  #   # Run specs in random order to surface order dependencies. If you find an
  #   # order dependency and want to debug it, you can fix the order by providing
  #   # the seed, which is printed after each run.
  #   #     --seed 1234
  #   config.order = :random
  #
  #   # Seed global randomization in this process using the `--seed` CLI option.
  #   # Setting this allows you to use `--seed` to deterministically reproduce
  #   # test failures related to randomization by passing the same `--seed` value
  #   # as the one that triggered the failure.
  #   Kernel.srand config.seed

  config.after(:all) { WebMock.reset! }
end

def stub_country_page
  stub_request(:get, 'https://wikipedia.com/page')
    .to_return(
      status: 200,
      body: <<~HTML
        <div id="mw-content-text">
          <ul>
            <li><a href="/resort-page"></a></li>
          </ul>
        </div>
      HTML
    )
end

def stub_resort_page
  stub_request(:get, 'https://en.wikipedia.org/resort-page')
    .to_return(
      status: 200,
      body: <<~HTML
        <h1>Some Resort</h1>
        <div class="geo">
          3°32′01″N 113°28′31″W
        </div>
        <div class="infobox-data">
          <div class="url">
            <a href="https://some-resort.com">Link</a>
          </div>
        </div>
      HTML
    )
end

def stub_geo_lookup(lat:, lng:)
  stub_request(:get, "https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=#{lat}&lon=#{lng}")
    .to_return(
      status: 200,
      body: {
        address: {
          city: 'Denver',
          state: 'Colorado',
          country: 'US'
        }
      }.to_json
    )
end

def stub_weather_api
  stub_request(:get, /api.open-meteo.com/).to_return do |request|
    query     = request.uri.query_values
    lats      = query.fetch('latitude').split(',').map(&:to_f)
    lons      = query.fetch('longitude').split(',').map(&:to_f)
    bodies    = lats.zip(lons).each_with_index.map do |(lat, lon), index|
      fake_location_json(lat: lat, lon: lon, base: lats.length > 1 && index.zero?)
    end

    { status: 200, body: bodies.length == 1 ? bodies.first : "[#{bodies.join(',')}]" }
  end
end

def weather_api_body(lat: 39.6403, lon: -106.3742)
  fake_location_json(lat: lat, lon: lon)
end

# A full build asks for ~3,600 locations; 97 seed buckets keep variety while generating each body once.
FAKE_BUCKETS = 97

def fake_seed(lat, lon)
  (((lat * 1000).round * 31) + (lon * 1000).round) % FAKE_BUCKETS
end

def fake_location_json(lat:, lon:, base: false)
  @fake_location_json                               ||= {}
  @fake_location_json[[fake_seed(lat, lon), base]] ||= fake_location(lat: lat, lon: lon, base: base).to_json
end

# Fixed "now" and coordinate-seeded profiles keep builds reproducible while covering every snow step.
STORM_TOTALS = [0.0, 0.4, 1.5, 4.0, 9.0, 16.0].freeze

def fake_location(lat:, lon:, base: false)
  rng     = Random.new(fake_seed(lat, lon))
  profile = rng.rand(STORM_TOTALS.length)
  days    = (0...19).map { |i| Date.new(2023, 3, 11) + i }
  scale   = base ? 0.6 : 1.0
  warm    = base ? 8 : 0

  daily_snow                = Array.new(days.length, 0.0)
  storm_day                 = 3 + rng.rand(10)
  daily_snow[storm_day]     = STORM_TOTALS[profile]
  daily_snow[storm_day + 1] = (STORM_TOTALS[profile] * 0.3).round(2)
  daily_snow[rng.rand(3)]   = rng.rand(0.5..3.0).round(2) if profile >= 2
  daily_snow                = daily_snow.map { |v| (v * scale).round(2) }

  high  = Array.new(days.length) { ((profile.zero? ? 45 : 28) + rng.rand(0..12) + warm).round(1) }
  low   = high.map { |t| (t - 12).round(1) }
  wind  = Array.new(days.length) { rng.rand(4.0..30.0).round(1) }
  hours = days.flat_map { |d| (0..23).map { |h| [d, h] } }

  hourly_snow = hours.each_with_index.map { |(_, h), i| h < 12 ? (daily_snow[i / 24] / 12.0).round(2) : 0.0 }
  hourly_temp = hours.each_with_index.map { |(_, h), i| (low[i / 24] + ((high[i / 24] - low[i / 24]) * Math.sin(Math::PI * h / 24.0))).round(1) }

  {
    'timezone' => 'America/Denver',
    'utc_offset_seconds' => -21_600,
    'current' => {
      'time' => '2023-03-14T12:00',
      'temperature_2m' => hourly_temp[(3 * 24) + 12],
      'relative_humidity_2m' => 65,
      'apparent_temperature' => (hourly_temp[(3 * 24) + 12] - 4).round(1),
      'is_day' => 1,
      'precipitation' => 0.0,
      'weather_code' => 2,
      'cloud_cover' => 40,
      'wind_speed_10m' => wind[3],
      'wind_direction_10m' => 225,
      'wind_gusts_10m' => (wind[3] * 1.6).round(1)
    },
    'hourly' => {
      'time' => hours.map { |d, h| "#{d.iso8601}T#{h.to_s.rjust(2, '0')}:00" },
      'temperature_2m' => hourly_temp,
      'relative_humidity_2m' => Array.new(hours.length, 70),
      'apparent_temperature' => hourly_temp.map { |t| (t - 4).round(1) },
      'precipitation_probability' => hourly_snow.map { |v| v.positive? ? 80 : 10 },
      'precipitation' => hourly_snow.map { |v| (v / 10.0).round(3) },
      'snowfall' => hourly_snow,
      'weather_code' => hourly_snow.map { |v| v.positive? ? 73 : 2 },
      'cloud_cover' => hourly_snow.map { |v| v.positive? ? 100 : 30 },
      'wind_speed_10m' => hours.each_index.map { |i| wind[i / 24] },
      'wind_direction_10m' => Array.new(hours.length, 250),
      'wind_gusts_10m' => hours.each_index.map { |i| (wind[i / 24] * 1.6).round(1) },
      'freezing_level_height' => hourly_temp.map { |t| (8000 + ((t - 28) * 250)).round },
      'snow_depth' => Array.new(hours.length, base ? 2.5 : 4.0),
      'visibility' => Array.new(hours.length, 20_000),
      'is_day' => hours.map { |_, h| h.between?(7, 18) ? 1 : 0 }
    },
    'daily' => {
      'time' => days.map(&:iso8601),
      'weather_code' => daily_snow.map { |v| v.positive? ? 73 : 2 },
      'temperature_2m_max' => high,
      'temperature_2m_min' => low,
      'apparent_temperature_max' => high.map { |t| (t - 4).round(1) },
      'apparent_temperature_min' => low.map { |t| (t - 4).round(1) },
      'sunrise' => days.map { |d| "#{d.iso8601}T06:30" },
      'sunset' => days.map { |d| "#{d.iso8601}T18:30" },
      'snowfall_sum' => daily_snow,
      'precipitation_sum' => daily_snow.map { |v| (v / 10.0).round(2) },
      'rain_sum' => Array.new(days.length, 0.0),
      'precipitation_hours' => daily_snow.map { |v| v.positive? ? 12.0 : 0.0 },
      'precipitation_probability_max' => daily_snow.map { |v| v.positive? ? 80 : 10 },
      'wind_speed_10m_max' => wind,
      'wind_gusts_10m_max' => wind.map { |w| (w * 1.6).round(1) },
      'wind_direction_10m_dominant' => Array.new(days.length, 250),
      'uv_index_max' => Array.new(days.length, 4.0),
      'sunshine_duration' => daily_snow.map { |v| v.positive? ? 3600 : 28_800 }
    }
  }
end
