# frozen_string_literal: true

require 'spec_helper'
require 'rack'
require 'tmpdir'

RSpec.describe('Date Sorting Feature', :js, type: :feature) do
  let(:build_dir) { @build_dir }

  before(:all) do
    stub_weather_api

    # Build site once
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

    # Set up Capybara to serve the static site
    build_directory = @build_dir
    Capybara.app    = Rack::Builder.new do
      use Rack::Static,
          urls: ['/'],
          root: build_directory,
          index: 'index.html',
          cascade: true

      run lambda { |env|
        path      = env['PATH_INFO']
        file_path = File.join(build_directory, path)

        if File.file?(file_path)
          [200, { 'Content-Type' => Rack::Mime.mime_type(File.extname(path)) }, [File.read(file_path)]]
        elsif File.file?(File.join(build_directory, "#{path}.html"))
          content = File.read(File.join(build_directory, "#{path}.html"))
          [200, { 'Content-Type' => 'text/html' }, [content]]
        else
          [404, { 'Content-Type' => 'text/html' }, ['Not Found']]
        end
      }
    end
  end

  after(:all) do
    FileUtils.rm_rf(@build_dir) if @build_dir && File.exist?(@build_dir)
  end

  describe 'state page' do
    it 'has sortable date column headers' do
      visit '/states/colorado'
      expect(page).to have_css('th.sortable-header')
    end

    it 'shows instruction text for sorting' do
      visit '/states/colorado'
      expect(page).to have_content('Click a date column to sort by snow depth')
    end

    it 'has cursor-pointer class on sortable headers' do
      visit '/states/colorado'

      headers = all('th.sortable-header')
      expect(headers.length).to be > 0

      headers.each do |header|
        expect(header['class']).to include('cursor-pointer')
      end
    end

    it 'sorts table when clicking a date header' do
      visit '/states/colorado'

      # Click the first sortable header
      first_header = find('th.sortable-header', match: :first)
      first_header.click

      # Should show sort indicator
      expect(first_header).to have_css('.sort-indicator', text: '↓')
      expect(page).to have_css('#forecast-body tr')
    end

    it 'resets to original order when clicking same header again' do
      visit '/states/colorado'

      # Get initial order of all resorts
      initial_order = all('#forecast-body tr td:first-child').map(&:text)

      # Click header to sort
      first_header = find('th.sortable-header', match: :first)
      first_header.click

      # Click same header again to reset
      first_header.click

      # Header should no longer have sorting-active class
      expect(first_header['class']).not_to include('sorting-active')

      # Should be back to original order
      final_order = all('#forecast-body tr td:first-child').map(&:text)
      expect(final_order).to eq(initial_order)
    end

    it 'has data-snow-values attribute on rows' do
      visit '/states/colorado'

      # Check that rows have the data attribute for sorting
      rows = all('#forecast-body tr[data-snow-values]')
      expect(rows.length).to be > 0
    end

    it 'changes sort indicator when clicking different headers' do
      visit '/states/colorado'

      headers = all('th.sortable-header')
      next if headers.length < 2

      # Click first header
      headers[0].click
      expect(headers[0]['class']).to include('sorting-active')

      # Click second header
      headers[1].click
      expect(headers[0]['class']).not_to include('sorting-active')
      expect(headers[1]['class']).to include('sorting-active')
    end
  end
end
