# frozen_string_literal: true

require_relative 'lib/follow_the_snow'
require 'fileutils'

sqlite_file = File.join(__dir__, 'data', 'features.sqlite')

def build!(resorts, logger_io: $stderr)
  build_dir = File.join(__dir__, 'docs')
  FileUtils.rm_rf(build_dir)
  builder   = FollowTheSnow::Builder::Site.new(
    build_dir: build_dir,
    resorts: resorts,
    source_dir: File.join(__dir__, 'pages'),
    logger_io: logger_io
  )

  builder.build!
  sh('minify docs/ --all --recursive -o docs/')
end

desc 'Build the site with the latest data from the SQLite database'
task :build do
  resorts = FollowTheSnow::Resort.from_sqlite(sqlite_file)
  build!(resorts)
end

desc 'Build the site with fake data for testing purposes'
task fast: [:css] do
  require 'webmock'
  require 'rspec'
  include WebMock::API

  WebMock.enable!
  WebMock.disable_net_connect!

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

  resorts = FollowTheSnow::Resort.from_sqlite(sqlite_file)
  # Suppress logging for faster builds
  build!(resorts)
end

desc 'Build the CSS files'
task :css do
  sh('npm run build')
end

desc 'Format the codebase'
task :fmt do
  sh('deno fmt .')
  sh('rubocop -A')
  sh('herb analyze pages/')
  sh('npx @herb-tools/formatter pages/')
end

desc 'Run the tests'
task :test do
  sh('bundle exec rspec')
end

desc 'Scrape the OpenSkiMap data and build the SQLite database'
task :scrape do
  builder = FollowTheSnow::OpenSkiMapBuilder.new(data_dir: File.join(__dir__, 'data'))
  builder.build!
end

desc 'Run accessibility and HTML validation checks'
task :a11y do
  puts '🔍 Running HTML validation with vnu...'
  sh('vnu --skip-non-html docs/index.html docs/about.html docs/snow-now.html docs/countries/united-states-of-america.html docs/states/colorado.html docs/resorts/wolf-creek-ski-area docs/404.html')

  puts "\n✅ HTML validation passed!"

  puts "\n📊 Starting local server for pa11y tests..."
  # Start a simple HTTP server in the background
  server_pid = spawn('ruby -run -ehttpd docs/ -p8000', out: '/dev/null', err: '/dev/null')

  # Wait for server to be ready
  max_attempts = 20
  server_ready = false
  max_attempts.times do |_i|
    sleep 0.5
    begin
      require 'net/http'
      response = Net::HTTP.get_response(URI('http://localhost:8000/'))
      if response.is_a?(Net::HTTPSuccess) || response.is_a?(Net::HTTPRedirection)
        server_ready = true
        break
      end
    rescue Errno::ECONNREFUSED, Errno::ECONNRESET
      # Server not ready yet, continue waiting
    end
  end

  raise 'Server failed to start' unless server_ready

  begin
    puts '🔍 Running pa11y-ci accessibility tests...'
    sh('pa11y-ci --config .pa11yci.json')
    puts "\n✅ Accessibility tests passed!"
  ensure
    puts "\n🛑 Stopping server..."
    Process.kill('TERM', server_pid)
    Process.wait(server_pid)
  end
end

task default: %i[fmt test build]
