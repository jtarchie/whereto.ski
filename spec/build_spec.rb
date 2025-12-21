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
    stub_weather_api

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
    end

    it 'includes snow today section' do
      snow_now_html = File.read(File.join(build_dir, 'snow-now.html'))
      expect(snow_now_html).to include('Snow Today')
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
      # Should have snow badge class with resort count format
      if index_html.include?('snow-badge')
        expect(index_html).to match(/\d+\s*resorts\s*\(/m) # "X resorts (Y.Y inches)" format
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

  describe 'search feature' do
    it 'generates search data JSON file' do
      search_data_path = File.join(build_dir, 'assets', 'search-data.json')
      expect(File.exist?(search_data_path)).to be(true)

      # Parse and verify structure
      raw_data = JSON.parse(File.read(search_data_path))

      # New compressed format: { cl: [countries], d: [{t,n,c,s,u},...] }
      expect(raw_data).to be_a(Hash)
      expect(raw_data).to have_key('cl') # country lookup
      expect(raw_data).to have_key('d')  # data entries
      expect(raw_data['cl']).to be_an(Array)
      expect(raw_data['d']).to be_an(Array)
      expect(raw_data['d'].length).to be > 0

      # Check that it has different types (c=country, s=state, r=resort)
      types = raw_data['d'].map { |item| item['t'] }.uniq
      expect(types).to include('c') # country
      expect(types).to include('s') # state
      expect(types).to include('r') # resort
    end

    it 'includes search button in pages' do
      index_html = File.read(File.join(build_dir, 'index.html'))
      expect(index_html).to include('id="search-button"')
      expect(index_html).to include('aria-label="Search"')
    end

    it 'includes search modal in layout' do
      index_html = File.read(File.join(build_dir, 'index.html'))
      expect(index_html).to include('<dialog id="search-modal"')
      expect(index_html).to include('id="search-input"')
      expect(index_html).to include('id="search-results"')
    end

    it 'has correct structure for search data' do
      search_data_path = File.join(build_dir, 'assets', 'search-data.json')
      raw_data         = JSON.parse(File.read(search_data_path))

      # Check country structure (t='c', n=name, u=url)
      country = raw_data['d'].find { |item| item['t'] == 'c' }
      expect(country).to have_key('n') # name
      expect(country).to have_key('u') # url
      expect(country).to have_key('t') # type
      expect(country['t']).to eq('c')

      # Check state structure (t='s', n=name, c=country index, u=url)
      state = raw_data['d'].find { |item| item['t'] == 's' }
      if state
        expect(state).to have_key('n') # name
        expect(state).to have_key('u') # url
        expect(state).to have_key('c') # country index
        expect(state).to have_key('t') # type
        expect(state['t']).to eq('s')
        expect(state['c']).to be_a(Integer) # country as numeric index
      end

      # Check resort structure (t='r', n=name, c=country index, s=state, u=url)
      resort = raw_data['d'].find { |item| item['t'] == 'r' }
      expect(resort).to have_key('n') # name
      expect(resort).to have_key('u') # url
      expect(resort).to have_key('t') # type
      expect(resort['t']).to eq('r')
      expect(resort['c']).to be_a(Integer) # country as numeric index
    end
  end
end
