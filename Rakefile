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
task :build, [:limit] => [:assets] do |_t, args|
  resorts = FollowTheSnow::Resort.from_sqlite(sqlite_file)
  if args[:limit]
    puts "Limiting to first #{args[:limit]} resorts for build"
    resorts = resorts.take(args[:limit].to_i)
  end
  build!(resorts)
end

desc 'Build the site with fake data for testing purposes'
task fast: [:assets] do
  require_relative 'spec/spec_helper'
  include WebMock::API

  WebMock.enable!
  WebMock.disable_net_connect!
  stub_weather_api

  resorts = FollowTheSnow::Resort.from_sqlite(sqlite_file)
  # Suppress logging for faster builds
  build!(resorts)
end

desc 'Build the CSS and JS files'
task :assets do
  sh('npm run build')
  sh('npx esbuild pages/input.js --bundle --minify --outfile=pages/public/assets/main.js')
  sh('npx esbuild pages/public/assets/main.css --minify --outfile=pages/public/assets/main.css')
end

desc 'Format the codebase'
task :fmt do
  sh('deno fmt .')
  sh('rubocop -A')
  sh('herb analyze pages/')
  sh('npx @herb-tools/formatter pages/')
end

desc 'Run the tests'
task test: [:assets] do
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

task default: %i[fast fmt test]
