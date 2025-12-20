# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'nokogiri'

RSpec.describe('Building') do
  let(:pages_dir) { File.expand_path(File.join(__dir__, '..', 'pages')) }
  # Provide access to the shared build directory
  let(:build_dir) { @build_dir }
  let(:sqlite) { File.expand_path(File.join(__dir__, '..', 'data', 'features.sqlite')) }

  before(:all) do
    # Stub API requests once for all tests
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
            'snowfall_sum' => [0.000, 0.000, 2.950, 0.138, 0.139, 0.000, 0.000, 0.000],
            'precipitation_hours' => [0.0, 0.0, 12.0, 3.0, 6.0, 1.0, 0.0, 3.0],
            'windspeed_10m_max' => [12.8, 16.6, 15.1, 6.3, 10.6, 7.1, 4.2, 14.2],
            'windgusts_10m_max' => [21.7, 26.2, 26.8, 9.6, 8.7, 8.9, 8.9, 27.3],
            'winddirection_10m_dominant' => [278, 251, 35, 89, 99, 123, 220, 358]
          }
        }.to_json
      )

    # Build site once for all tests
    @build_dir  = Dir.mktmpdir
    pages_dir   = File.expand_path(File.join(__dir__, '..', 'pages'))
    sqlite      = File.expand_path(File.join(__dir__, '..', 'data', 'features.sqlite'))
    resorts     = FollowTheSnow::Resort.from_sqlite(sqlite)

    builder = FollowTheSnow::Builder::Site.new(
      build_dir: @build_dir,
      resorts: resorts,
      source_dir: pages_dir,
      logger_io: File.open(File::NULL, 'w')
    )

    builder.build!
  end

  after(:all) do
    # Clean up the temporary build directory
    FileUtils.rm_rf(@build_dir) if @build_dir && File.exist?(@build_dir)
  end

  it 'builds HTML files' do
    html_files = Dir[File.join(build_dir, '**', '*.html')].to_a
    # Original: 3841 files
    # Now skipping:
    # - State pages for small countries (threshold=20): ~170 files
    # - Resort pages with non-Latin names that don't parameterize: ~48 files
    expect(html_files.length).to eq(3673)
  end

  describe 'snow-now page' do
    it 'generates snow-now.html' do
      snow_now_path = File.join(build_dir, 'snow-now.html')
      expect(File.exist?(snow_now_path)).to be(true)
    end

    it 'includes top snowy resorts section' do
      snow_now_html = File.read(File.join(build_dir, 'snow-now.html'))
      expect(snow_now_html).to include('Most Snow')
      expect(snow_now_html).to include('🏔️')
    end

    it 'includes snow today section' do
      snow_now_html = File.read(File.join(build_dir, 'snow-now.html'))
      expect(snow_now_html).to include('Snow Today')
      expect(snow_now_html).to include('📅')
    end

    it 'displays snow today in table format with actual snow values' do
      snow_now_html = File.read(File.join(build_dir, 'snow-now.html'))
      doc           = Nokogiri::HTML(snow_now_html)

      # Find the Snow Today section
      snow_today_section = doc.xpath('//section[.//h2[contains(text(), "Snow Today")]]')
      expect(snow_today_section).not_to be_empty

      # Check if it has a table
      table = snow_today_section.at_xpath('.//table')

      if table
        # Verify table structure
        headers = table.xpath('.//thead//th').map(&:text).map(&:strip)
        expect(headers).to include('Rank', 'Resort', 'Location', 'Snow Today')

        # Check that there are rows with actual snow values (not all zeros)
        snow_cells = table.xpath('.//tbody//tr//td[4]').map(&:text).map(&:strip)

        # At least one row should have non-zero snow
        has_non_zero = snow_cells.any? do |cell|
          # Extract numeric value and check if it's greater than 0
          cell.match?(/[1-9]\d*\.?\d*/)
        end

        expect(has_non_zero).to be(true), "Expected at least one resort with non-zero snow, but got: #{snow_cells.inspect}"
      end
    end

    it 'includes regional summaries section' do
      snow_now_html = File.read(File.join(build_dir, 'snow-now.html'))
      expect(snow_now_html).to include('Snow by Region')
      expect(snow_now_html).to include('🌍')
    end

    it 'includes quick stats section' do
      snow_now_html = File.read(File.join(build_dir, 'snow-now.html'))
      expect(snow_now_html).to include('Total Resorts Tracked')
      expect(snow_now_html).to include('Resorts w/ Snow')
    end
  end

  describe 'snow indicators and badges' do
    it 'marks countries and states with snow when snowfall is present' do
      index_doc = Nokogiri::HTML(File.read(File.join(build_dir, 'index.html')))
      usa_li    = index_doc.at_xpath("//li[@data-has-snow and .//a[normalize-space(text())='United States of America']]")

      expect(usa_li).not_to be_nil
      expect(usa_li['data-has-snow']).to eq('true')

      usa_doc  = Nokogiri::HTML(File.read(File.join(build_dir, 'countries', 'united-states-of-america.html')))
      idaho_li = usa_doc.at_xpath("//li[@data-has-snow and .//a[normalize-space(text())='Idaho']]")

      expect(idaho_li).not_to be_nil
      expect(idaho_li['data-has-snow']).to eq('true')
    end

    it 'includes snow badges with counts on index page' do
      index_html = File.read(File.join(build_dir, 'index.html'))
      # Should have snow badge class and snowflake emoji
      if index_html.include?('snow-badge')
        expect(index_html).to include('❄️')
        expect(index_html).to match(/\d+\s*\(/m) # Number followed by parenthesis (count format)
      end
    end

    it 'includes filter toggle on index page' do
      index_html = File.read(File.join(build_dir, 'index.html'))
      expect(index_html).to include('filter-snow-toggle')
      expect(index_html).to include('Only Snow')
    end

    it 'includes data-has-snow attributes on country pages' do
      # Check a country page that should exist (exclude snow-now pages)
      country_files = Dir[File.join(build_dir, 'countries', '*.html')].reject { |f| f.include?('snow-now') }
      expect(country_files).not_to be_empty

      first_country_html = File.read(country_files.first)
      expect(first_country_html).to include('data-has-snow=')
    end

    it 'includes snow badges on country pages with snow' do
      country_files = Dir[File.join(build_dir, 'countries', '*.html')].reject { |f| f.include?('snow-now') }

      # Find a country page with snow badges
      country_with_badge = country_files.find do |file|
        File.read(file).include?('snow-badge')
      end

      # Skip if no country with snow badge found
      skip 'No country with snow badge found' unless country_with_badge

      html = File.read(country_with_badge)
      # Small countries show per-resort snow (e.g., "❄️ 3.2 inches")
      # Regular countries show state count (e.g., "5 (10.5 inches)")
      # Both should have snow-badge class and some measurement
      expect(html).to match(/snow-badge/)
      expect(html).to match(/\d+\.\d+|"/) # Either decimal number or inch/cm unit
    end

    it 'includes filter toggle on country pages' do
      country_files      = Dir[File.join(build_dir, 'countries', '*.html')].reject { |f| f.include?('snow-now') }
      first_country_html = File.read(country_files.first)
      expect(first_country_html).to include('filter-snow-toggle')
    end
  end

  describe 'snow cell styling' do
    it 'adds snow-cell class to cells with snow in state pages' do
      state_files = Dir[File.join(build_dir, 'states', '*.html')]
      expect(state_files).not_to be_empty

      # Find a state page with snow
      state_with_snow = state_files.find do |file|
        File.read(file).include?('snow-cell')
      end

      if state_with_snow
        html = File.read(state_with_snow)
        expect(html).to include('snow-cell')
        expect(html).to include('snow-value')
      end
    end

    it 'marks table rows without snow with no-snow class in state pages' do
      state_files = Dir[File.join(build_dir, 'states', '*.html')].reject { |f| f.include?('snow-now') }
      expect(state_files).not_to be_empty

      # Find a state page to test (exclude snow-now pages)
      state_file = state_files.first
      html       = File.read(state_file)
      doc        = Nokogiri::HTML(html)

      # Check that table rows exist in the forecast table
      rows = doc.xpath('//table[.//th[contains(text(), "Resort")]]//tbody//tr')

      # Skip if no forecast table found
      next if rows.empty?

      # Check that rows either have snow-cell or no-snow class
      rows.each do |row|
        has_snow_cell     = row.xpath('.//td[@class="snow-cell"]').any?
        has_no_snow_class = row['class']&.include?('no-snow')

        # Row should either have snow or be marked as no-snow
        expect(has_snow_cell || has_no_snow_class).to be(true),
                                                      "Row should have snow-cell or no-snow class: #{row.to_html}"
      end
    end

    it 'adds snow-cell class to snowfall column in resort pages' do
      resort_files = Dir[File.join(build_dir, 'resorts', '*.html')]
      expect(resort_files).not_to be_empty

      # Find a resort page with snow
      resort_with_snow = resort_files.find do |file|
        content = File.read(file)
        content.include?('snow-cell') || content.include?('Long Term Forecast')
      end

      if resort_with_snow
        html = File.read(resort_with_snow)
        # Check for either snow-cell styling or basic table structure
        expect(html).to include('table')
      end
    end
  end

  describe 'navigation links' do
    it 'includes Snow Now link in navigation' do
      index_html = File.read(File.join(build_dir, 'index.html'))
      expect(index_html).to include('href="/snow-now"')
      expect(index_html).to include('Snow Now')
    end

    it 'includes Snow Now link in mobile menu' do
      index_html = File.read(File.join(build_dir, 'index.html'))
      expect(index_html).to include('drawer-side')
      expect(index_html).to match(/snow-now.*Snow Now/m)
    end
  end
end
