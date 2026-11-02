# frozen_string_literal: true

require_relative 'lib/follow_the_snow'
require 'fileutils'

sqlite_file = File.join(__dir__, 'data', 'features.sqlite')

def build!(resorts, logger_io: $stderr, minify: true)
  build_dir = File.join(__dir__, 'docs')
  FileUtils.rm_rf(build_dir)
  builder   = FollowTheSnow::Builder::Site.new(
    build_dir: build_dir,
    resorts: resorts,
    source_dir: File.join(__dir__, 'pages'),
    logger_io: logger_io
  )

  builder.build!
  sh('minify docs/ --all --recursive -o docs/') if minify
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
  build!(resorts, minify: false)
end

desc 'Build the CSS and JS files'
task :assets do
  sh('npm run build')
  sh('npx esbuild pages/input.js --bundle --minify --outfile=pages/public/assets/main.js')
  # map.js stays an ES module importing MapLibre's own files, which locate their worker relative to themselves.
  sh('npx esbuild pages/map.js --minify --format=esm --outfile=pages/public/assets/map.js')
  FileUtils.mkdir_p('pages/public/assets/maplibre')
  FileUtils.cp(%w[maplibre-gl.mjs maplibre-gl-worker.mjs maplibre-gl.css].map { |f| "node_modules/maplibre-gl/dist/#{f}" }, 'pages/public/assets/maplibre')
  sh('npx esbuild pages/public/assets/main.css --minify --allow-overwrite --outfile=pages/public/assets/main.css')
end

desc 'Format the codebase'
task :fmt do
  sh('rubocop -A')
  sh('npx --no-install @herb-tools/linter pages/ --fix')
  sh('npx --no-install @herb-tools/formatter pages/')
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
  sh('vnu --skip-non-html docs/index.html docs/about.html docs/countries/united-states-of-america.html docs/countries/andorra.html docs/states/colorado.html docs/resorts/wolf-creek-ski-area.html docs/404.html')

  puts "\n✅ HTML validation passed!"

  puts "\n📊 Starting local server for pa11y tests..."
  require 'webrick'
  server = WEBrick::HTTPServer.new(Port: 8000, DocumentRoot: 'docs', Logger: WEBrick::Log.new(File::NULL), AccessLog: [])
  thread = Thread.new { server.start }

  begin
    puts '🔍 Running pa11y-ci accessibility tests...'
    sh('pa11y-ci --config .pa11yci.json')
    puts "\n✅ Accessibility tests passed!"
  ensure
    puts "\n🛑 Stopping server..."
    server.shutdown
    thread.join
  end
end

task default: %i[fast fmt test]
