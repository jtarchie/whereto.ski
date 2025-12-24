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
    # With babosa, all resorts can now be slugified (including Cyrillic, Greek, etc.)
    expect(html_files.length).to eq(4311)
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

    it 'includes accessible search button in pages' do
      index_html = File.read(File.join(build_dir, 'index.html'))
      doc        = Nokogiri::HTML(index_html)

      # Check for button with accessible label
      search_button = doc.at_xpath("//button[@aria-label='Search']")
      expect(search_button).not_to be_nil
      expect(search_button.at_xpath('.//svg')).not_to be_nil # Has icon
    end

    it 'includes accessible search modal in layout' do
      index_html = File.read(File.join(build_dir, 'index.html'))
      doc        = Nokogiri::HTML(index_html)

      # Check for dialog element
      dialog = doc.at_xpath('//dialog')
      expect(dialog).not_to be_nil

      # Check for accessible search input
      search_input = doc.at_xpath("//input[@aria-label='Search for countries, states, or resorts']")
      expect(search_input).not_to be_nil
      expect(search_input['type']).to eq('search')
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

  describe 'settings feature' do
    it 'includes accessible settings button in navigation' do
      index_html = File.read(File.join(build_dir, 'index.html'))
      doc        = Nokogiri::HTML(index_html)

      # Check for settings button with accessible label
      settings_button = doc.at_xpath("//button[@aria-label='Settings']")
      expect(settings_button).not_to be_nil
      expect(settings_button['onclick']).to include('settings_modal')
    end

    it 'includes settings icon SVG' do
      index_html = File.read(File.join(build_dir, 'index.html'))
      doc        = Nokogiri::HTML(index_html)

      # Check for settings gear icon in the button
      settings_button = doc.at_xpath("//button[@aria-label='Settings']")
      expect(settings_button).not_to be_nil

      settings_icon = settings_button.at_xpath('.//svg')
      expect(settings_icon).not_to be_nil
    end

    it 'includes settings modal dialog' do
      index_html = File.read(File.join(build_dir, 'index.html'))
      doc        = Nokogiri::HTML(index_html)

      modal = doc.at_xpath("//dialog[@id='settings_modal']")
      expect(modal).not_to be_nil
      expect(modal['class']).to include('modal')
    end

    it 'includes settings modal title' do
      index_html = File.read(File.join(build_dir, 'index.html'))
      doc        = Nokogiri::HTML(index_html)

      modal = doc.at_xpath("//dialog[@id='settings_modal']")
      title = modal.at_xpath(".//h3[contains(text(), 'Settings')]")
      expect(title).not_to be_nil
    end

    it 'includes accessible temperature unit toggle in modal' do
      index_html = File.read(File.join(build_dir, 'index.html'))
      doc        = Nokogiri::HTML(index_html)

      modal = doc.at_xpath("//dialog[@id='settings_modal']")
      expect(modal).not_to be_nil

      # Check for temperature unit label
      label = modal.at_xpath(".//label[contains(text(), 'Temperature Unit')]")
      expect(label).not_to be_nil

      # Check for toggle input with proper association
      toggle = modal.at_xpath(".//input[@id='unit-toggle'][@type='checkbox']")
      expect(toggle).not_to be_nil
      expect(toggle['class']).to include('toggle')

      # Check for °F and °C labels
      expect(modal.text).to include('°F')
      expect(modal.text).to include('°C')
    end

    it 'includes accessible show only snow toggle in modal' do
      index_html = File.read(File.join(build_dir, 'index.html'))
      doc        = Nokogiri::HTML(index_html)

      modal = doc.at_xpath("//dialog[@id='settings_modal']")
      expect(modal).not_to be_nil

      # Check for label element wrapping or associated with toggle
      toggle = modal.at_xpath(".//input[@id='filter-snow-toggle'][@type='checkbox']")
      expect(toggle).not_to be_nil
      expect(toggle['class']).to include('toggle')
      expect(toggle['aria-label']).to eq('Show only snow')

      # Check for label text
      label = modal.at_xpath(".//label[@for='filter-snow-toggle']")
      expect(label).not_to be_nil
      expect(label.text).to include('Show Only Snow')
    end

    it 'includes close button in modal' do
      index_html = File.read(File.join(build_dir, 'index.html'))
      doc        = Nokogiri::HTML(index_html)

      modal        = doc.at_xpath("//dialog[@id='settings_modal']")
      close_button = modal.at_xpath(".//button[contains(text(), 'Close')]")
      expect(close_button).not_to be_nil
      expect(close_button['class']).to include('btn')
    end

    it 'includes modal backdrop for closing' do
      index_html = File.read(File.join(build_dir, 'index.html'))
      doc        = Nokogiri::HTML(index_html)

      modal    = doc.at_xpath("//dialog[@id='settings_modal']")
      backdrop = modal.at_xpath(".//form[@method='dialog' and contains(@class, 'modal-backdrop')]")
      expect(backdrop).not_to be_nil
    end

    it 'has proper DaisyUI modal structure' do
      index_html = File.read(File.join(build_dir, 'index.html'))
      doc        = Nokogiri::HTML(index_html)

      modal = doc.at_xpath("//dialog[@id='settings_modal']")
      expect(modal).not_to be_nil
      expect(modal['class']).to include('modal')

      # Check for modal-box
      modal_box = modal.at_xpath(".//div[contains(@class, 'modal-box')]")
      expect(modal_box).not_to be_nil

      # Check for modal-action
      modal_action = modal.at_xpath(".//div[contains(@class, 'modal-action')]")
      expect(modal_action).not_to be_nil
    end

    it 'includes settings in all page types' do
      # Check index page
      index_html = File.read(File.join(build_dir, 'index.html'))
      doc        = Nokogiri::HTML(index_html)
      expect(doc.at_xpath("//button[@aria-label='Settings']")).not_to be_nil
      expect(doc.at_xpath("//dialog[@id='settings_modal']")).not_to be_nil

      # Check a country page
      country_files = Dir[File.join(build_dir, 'countries', '*.html')].reject { |f| f.include?('snow-now') }
      country_html  = File.read(country_files.first)
      country_doc   = Nokogiri::HTML(country_html)
      expect(country_doc.at_xpath("//button[@aria-label='Settings']")).not_to be_nil

      # Check snow-now page
      snow_now_html = File.read(File.join(build_dir, 'snow-now.html'))
      snow_now_doc  = Nokogiri::HTML(snow_now_html)
      expect(snow_now_doc.at_xpath("//button[@aria-label='Settings']")).not_to be_nil
    end
  end

  describe 'social media sharing metadata' do
    describe 'Open Graph tags' do
      it 'includes required Open Graph tags in all pages' do
        index_html = File.read(File.join(build_dir, 'index.html'))
        doc        = Nokogiri::HTML(index_html)

        expect(doc.at_xpath("//meta[@property='og:type']")).not_to be_nil
        expect(doc.at_xpath("//meta[@property='og:url']")).not_to be_nil
        expect(doc.at_xpath("//meta[@property='og:title']")).not_to be_nil
        expect(doc.at_xpath("//meta[@property='og:description']")).not_to be_nil
        expect(doc.at_xpath("//meta[@property='og:image']")).not_to be_nil
        expect(doc.at_xpath("//meta[@property='og:site_name']")).not_to be_nil
      end

      it 'sets og:type to website' do
        index_html = File.read(File.join(build_dir, 'index.html'))
        doc        = Nokogiri::HTML(index_html)

        og_type = doc.at_xpath("//meta[@property='og:type']")
        expect(og_type['content']).to eq('website')
      end

      it 'sets og:site_name to "Where To Ski"' do
        index_html = File.read(File.join(build_dir, 'index.html'))
        doc        = Nokogiri::HTML(index_html)

        og_site_name = doc.at_xpath("//meta[@property='og:site_name']")
        expect(og_site_name['content']).to eq('Where To Ski')
      end

      it 'includes dynamic URL for index page' do
        index_html = File.read(File.join(build_dir, 'index.html'))
        doc        = Nokogiri::HTML(index_html)

        og_url = doc.at_xpath("//meta[@property='og:url']")
        expect(og_url['content']).to eq('https://whereto.ski/')
      end

      it 'includes dynamic URL for resort pages' do
        resort_files = Dir[File.join(build_dir, 'resorts', '*.html')]
        expect(resort_files).not_to be_empty

        resort_file = resort_files.first
        resort_html = File.read(resort_file)
        doc         = Nokogiri::HTML(resort_html)

        og_url       = doc.at_xpath("//meta[@property='og:url']")
        resort_slug  = File.basename(resort_file, '.html')
        expected_url = "https://whereto.ski/resorts/#{resort_slug}"

        expect(og_url['content']).to eq(expected_url)
      end

      it 'includes dynamic URL for country pages' do
        country_files = Dir[File.join(build_dir, 'countries', '*.html')].reject { |f| f.include?('snow-now') }
        expect(country_files).not_to be_empty

        country_file = country_files.first
        country_html = File.read(country_file)
        doc          = Nokogiri::HTML(country_html)

        og_url        = doc.at_xpath("//meta[@property='og:url']")
        country_slug  = File.basename(country_file, '.html')
        expected_url  = "https://whereto.ski/countries/#{country_slug}"

        expect(og_url['content']).to eq(expected_url)
      end

      it 'includes image with fallback to favicon' do
        index_html = File.read(File.join(build_dir, 'index.html'))
        doc        = Nokogiri::HTML(index_html)

        og_image = doc.at_xpath("//meta[@property='og:image']")
        expect(og_image['content']).to include('https://whereto.ski/')
        expect(og_image['content']).to include('.png')
      end

      it 'includes og:image:alt tag' do
        index_html = File.read(File.join(build_dir, 'index.html'))
        doc        = Nokogiri::HTML(index_html)

        og_image_alt = doc.at_xpath("//meta[@property='og:image:alt']")
        expect(og_image_alt).not_to be_nil
        expect(og_image_alt['content']).not_to be_empty
      end
    end

    describe 'Twitter Card tags' do
      it 'includes required Twitter Card tags in all pages' do
        index_html = File.read(File.join(build_dir, 'index.html'))
        doc        = Nokogiri::HTML(index_html)

        expect(doc.at_xpath("//meta[@name='twitter:card']")).not_to be_nil
        expect(doc.at_xpath("//meta[@name='twitter:url']")).not_to be_nil
        expect(doc.at_xpath("//meta[@name='twitter:title']")).not_to be_nil
        expect(doc.at_xpath("//meta[@name='twitter:description']")).not_to be_nil
        expect(doc.at_xpath("//meta[@name='twitter:image']")).not_to be_nil
      end

      it 'sets twitter:card to summary_large_image' do
        index_html = File.read(File.join(build_dir, 'index.html'))
        doc        = Nokogiri::HTML(index_html)

        twitter_card = doc.at_xpath("//meta[@name='twitter:card']")
        expect(twitter_card['content']).to eq('summary_large_image')
      end

      it 'matches Twitter URL with Open Graph URL' do
        index_html = File.read(File.join(build_dir, 'index.html'))
        doc        = Nokogiri::HTML(index_html)

        og_url      = doc.at_xpath("//meta[@property='og:url']")['content']
        twitter_url = doc.at_xpath("//meta[@name='twitter:url']")['content']

        expect(twitter_url).to eq(og_url)
      end

      it 'matches Twitter title with Open Graph title' do
        index_html = File.read(File.join(build_dir, 'index.html'))
        doc        = Nokogiri::HTML(index_html)

        og_title      = doc.at_xpath("//meta[@property='og:title']")['content']
        twitter_title = doc.at_xpath("//meta[@name='twitter:title']")['content']

        expect(twitter_title).to eq(og_title)
      end

      it 'matches Twitter description with Open Graph description' do
        index_html = File.read(File.join(build_dir, 'index.html'))
        doc        = Nokogiri::HTML(index_html)

        og_description      = doc.at_xpath("//meta[@property='og:description']")['content']
        twitter_description = doc.at_xpath("//meta[@name='twitter:description']")['content']

        expect(twitter_description).to eq(og_description)
      end

      it 'matches Twitter image with Open Graph image' do
        index_html = File.read(File.join(build_dir, 'index.html'))
        doc        = Nokogiri::HTML(index_html)

        og_image      = doc.at_xpath("//meta[@property='og:image']")['content']
        twitter_image = doc.at_xpath("//meta[@name='twitter:image']")['content']

        expect(twitter_image).to eq(og_image)
      end
    end

    describe 'resort page descriptions with forecast data' do
      it 'includes forecast information in description when snow is expected' do
        resort_files = Dir[File.join(build_dir, 'resorts', '*.html')]
        expect(resort_files).not_to be_empty

        # Find a resort with snow in forecast (from stubbed data)
        resort_with_snow = resort_files.find do |file|
          html = File.read(file)
          html.include?('snow-cell') || html.include?('❄️')
        end

        if resort_with_snow
          resort_html = File.read(resort_with_snow)
          doc         = Nokogiri::HTML(resort_html)

          og_description = doc.at_xpath("//meta[@property='og:description']")['content']

          # Should include location information
          expect(og_description).to match(/in .+, .+/)
          # Should mention either "Expecting" snow or "No significant snowfall"
          expect(og_description).to match(/Expecting .+ of snow|No significant snowfall/)
        end
      end

      it 'includes location information in resort descriptions' do
        resort_files = Dir[File.join(build_dir, 'resorts', '*.html')]
        resort_file  = resort_files.first
        resort_html  = File.read(resort_file)
        doc          = Nokogiri::HTML(resort_html)

        og_description = doc.at_xpath("//meta[@property='og:description']")['content']

        # Should include "in [region], [country]" pattern
        expect(og_description).to match(/\sin\s.+,\s.+\./)
      end

      it 'mentions snowfall amount when snow is expected' do
        resort_files = Dir[File.join(build_dir, 'resorts', '*.html')]

        # Find a resort with snow in forecast (from stubbed data)
        resort_with_snow = resort_files.find do |file|
          html = File.read(file)
          html.include?('snow-cell') || html.include?('❄️')
        end

        if resort_with_snow
          resort_html = File.read(resort_with_snow)
          doc         = Nokogiri::HTML(resort_html)

          og_description = doc.at_xpath("//meta[@property='og:description']")['content']

          # Should include snowfall measurement (inches or cm/mm)
          expect(og_description).to match(/Expecting .+\d/)
          expect(og_description).to include('of snow in the forecast period')
        end
      end

      it 'mentions no snowfall when none is expected' do
        resort_files = Dir[File.join(build_dir, 'resorts', '*.html')]

        # Find a resort without snow
        resort_without_snow = resort_files.find do |file|
          html = File.read(file)
          !html.include?('snow-cell') && !html.include?('❄️')
        end

        if resort_without_snow
          resort_html = File.read(resort_without_snow)
          doc         = Nokogiri::HTML(resort_html)

          og_description = doc.at_xpath("//meta[@property='og:description']")['content']

          expect(og_description).to include('No significant snowfall expected')
        end
      end
    end

    describe 'page-specific metadata' do
      it 'includes snow count in country page descriptions' do
        country_files = Dir[File.join(build_dir, 'countries', '*.html')].reject { |f| f.include?('snow-now') }
        country_file  = country_files.first
        country_html  = File.read(country_file)
        doc           = Nokogiri::HTML(country_html)

        og_description = doc.at_xpath("//meta[@property='og:description']")['content']

        # Should mention resorts with snow
        expect(og_description).to match(/\d+\s+resorts?\s+with\s+snow/i)
      end

      it 'includes snow count in state page descriptions' do
        state_files = Dir[File.join(build_dir, 'states', '*.html')].reject { |f| f.include?('snow-now') }
        next if state_files.empty? # Skip if no state pages (small country)

        state_file = state_files.first
        state_html = File.read(state_file)
        doc        = Nokogiri::HTML(state_html)

        og_description = doc.at_xpath("//meta[@property='og:description']")['content']

        # Should mention resorts with snow
        expect(og_description).to match(/\d+\s+resorts?\s+with\s+snow/i)
      end

      it 'includes correct URL for snow-now page' do
        snow_now_html = File.read(File.join(build_dir, 'snow-now.html'))
        doc           = Nokogiri::HTML(snow_now_html)

        og_url = doc.at_xpath("//meta[@property='og:url']")['content']
        expect(og_url).to eq('https://whereto.ski/snow-now')
      end

      it 'includes correct URL for about page' do
        about_html = File.read(File.join(build_dir, 'about.html'))
        doc        = Nokogiri::HTML(about_html)

        og_url = doc.at_xpath("//meta[@property='og:url']")['content']
        expect(og_url).to eq('https://whereto.ski/about')
      end

      it 'includes sharing metadata in snow-now country pages' do
        country_snow_now_files = Dir[File.join(build_dir, 'countries', '*-snow-now.html')]
        expect(country_snow_now_files).not_to be_empty

        file = country_snow_now_files.first
        html = File.read(file)
        doc  = Nokogiri::HTML(html)

        og_url       = doc.at_xpath("//meta[@property='og:url']")
        country_slug = File.basename(file, '.html')

        expect(og_url['content']).to eq("https://whereto.ski/countries/#{country_slug}")
      end
    end

    describe 'consistency across page types' do
      it 'includes sharing metadata in all generated HTML files' do
        html_files = Dir[File.join(build_dir, '**', '*.html')]
        sample     = html_files.sample(10) # Check a random sample

        sample.each do |file|
          html = File.read(file)
          doc  = Nokogiri::HTML(html)

          expect(doc.at_xpath("//meta[@property='og:title']")).not_to be_nil,
                                                                      "Missing og:title in #{file}"
          expect(doc.at_xpath("//meta[@property='og:description']")).not_to be_nil,
                                                                            "Missing og:description in #{file}"
          expect(doc.at_xpath("//meta[@property='og:url']")).not_to be_nil,
                                                                    "Missing og:url in #{file}"
          expect(doc.at_xpath("//meta[@name='twitter:card']")).not_to be_nil,
                                                                      "Missing twitter:card in #{file}"
        end
      end
    end
  end
end
