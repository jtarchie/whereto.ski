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

RSpec.configure do |config|
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
  stub_request(:get, /api.open-meteo.com/)
    .to_return(
      status: 200,
      body: {
        'daily' => {
          'time' => %w[
            2023-03-14 2023-03-15 2023-03-16 2023-03-17 2023-03-18 2023-03-19 2023-03-20 2023-03-21
          ],
          'weathercode' => [3, 3, 75, 71, 73, 51, 3, 51],
          'temperature_2m_max' => [62.2, 67.6, 50.7, 38.4, 41.1, 46.7, 54.9, 58.7],
          'temperature_2m_min' => [36.8, 42.5, 23.7, 19.8, 28.5, 29.4, 35.5, 41.3],
          'apparent_temperature_max' => [58.3, 63.2, 45.1, 32.6, 36.8, 42.3, 51.2, 55.4],
          'apparent_temperature_min' => [32.1, 38.9, 18.4, 14.2, 23.7, 25.1, 31.8, 38.2],
          'snowfall_sum' => [0.000, 0.000, 2.950, 0.138, 0.139, 0.000, 0.000, 0.000],
          'precipitation_hours' => [0.0, 0.0, 12.0, 3.0, 6.0, 1.0, 0.0, 3.0],
          'precipitation_probability_max' => [5, 10, 85, 45, 60, 20, 5, 35],
          'windspeed_10m_max' => [12.8, 16.6, 15.1, 6.3, 10.6, 7.1, 4.2, 14.2],
          'windgusts_10m_max' => [21.7, 26.2, 26.8, 9.6, 8.7, 8.9, 8.9, 27.3],
          'winddirection_10m_dominant' => [278, 251, 35, 89, 99, 123, 220, 358],
          'uv_index_max' => [4.2, 5.8, 2.1, 3.4, 4.7, 5.3, 6.1, 5.9],
          'sunshine_duration' => [21_600, 28_800, 7200, 14_400, 18_000, 25_200, 32_400, 27_000]
        }
      }.to_json
    )
end
