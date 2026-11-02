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
    stub_weather_api
    SharedBuild.perform!
    @build_dir = SharedBuild.build_dir
  end

  it 'builds HTML files' do
    html_files = Dir[File.join(build_dir, '**', '*.html')].to_a
    # Original: 3841 files
    # Now skipping:
    # - State pages for small countries (threshold=20): ~170 files
    # With stringex, all resorts can be slugified with excellent transliteration
    # - Snow Now pages (now 301s in _redirects): 365 files
    # - Duplicate resorts dropped; same-URL resorts that overwrote each other now each get a page: net +7
    expect(html_files.length).to eq(3954)
    expect(File.readlines(File.join(build_dir, '_redirects')).length).to eq(364) # Tolmin (SI) only held a duplicate of Vogel
  end

  describe 'list pages' do
    def doc_for(*path)
      Nokogiri::HTML(File.read(File.join(build_dir, *path)))
    end

    it 'leads home with the top 25 resorts worldwide, then countries ranked' do
      doc = doc_for('index.html')

      expect(doc.css('[data-ranked] tbody tr').length).to eq(25)
      expect(doc.at_css('header p').text.squish).to match(/Snow in the next 7 days at \d+ of \d+ resorts worldwide/)
      expect(doc.css('table.areas tbody tr td:first-child a').map(&:text)).to include('United States of America')
    end

    it 'shows large countries as top 25 plus regions' do
      doc = doc_for('countries', 'united-states-of-america.html')

      expect(doc.css('[data-ranked] tbody tr').length).to eq(25)
      expect(doc.css('#regions-heading')).not_to be_empty
      expect(doc.css('section a').map { |a| a['href'] }).to include('/states/colorado')
    end

    it 'shows small countries as every resort, with no regions' do
      doc = doc_for('countries', 'andorra.html')

      expect(doc.css('[data-ranked] tbody tr').length).to eq(4)
      expect(doc.css('#regions-heading')).to be_empty
    end

    it 'keeps the snow-only filter hook on list pages' do
      %w[index.html countries/united-states-of-america.html].each do |page|
        html = File.read(File.join(build_dir, page))

        expect(html).to include('filter-snow-toggle', 'data-has-snow=')
      end
    end

    it 'lists every page in sitemap.xml at its canonical URL, and points robots.txt at it' do
      sitemap = Nokogiri::XML(File.read(File.join(build_dir, 'sitemap.xml')))
      locs    = sitemap.xpath('//xmlns:loc').map(&:text)

      expect(locs).to include('https://whereto.ski/', 'https://whereto.ski/about', 'https://whereto.ski/resorts/steamboat-ski-resort')
      expect(locs.length).to eq(Dir[File.join(build_dir, '**', '*.html')].length - 1)
      expect(locs.grep(/404|\.html/)).to be_empty
      expect(File.read(File.join(build_dir, 'robots.txt'))).to include('Sitemap: https://whereto.ski/sitemap.xml')
    end

    it 'retires Snow Now pages with 301s to their parent scope' do
      expect(Dir[File.join(build_dir, '**', '*snow-now*')]).to be_empty

      redirects = File.read(File.join(build_dir, '_redirects')).lines.map(&:chomp)

      expect(redirects).to include('/snow-now / 301',
                                   '/countries/united-states-of-america-snow-now /countries/united-states-of-america 301',
                                   '/states/colorado-snow-now /states/colorado 301')
      expect(redirects.grep(%r{/states/(andorra|canillo)})).to be_empty
      expect(redirects.length).to be < 2000
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
      search_input = doc.at_xpath("//input[@aria-label='Search for countries, regions, or resorts']")
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
      expect(modal['class']).to include('dialog')
    end

    it 'includes settings modal title' do
      index_html = File.read(File.join(build_dir, 'index.html'))
      doc        = Nokogiri::HTML(index_html)

      modal = doc.at_xpath("//dialog[@id='settings_modal']")
      title = modal.at_xpath(".//h2[contains(text(), 'Settings')]")
      expect(title).not_to be_nil
    end

    it 'includes accessible temperature unit toggle in modal' do
      index_html = File.read(File.join(build_dir, 'index.html'))
      doc        = Nokogiri::HTML(index_html)

      modal = doc.at_xpath("//dialog[@id='settings_modal']")
      expect(modal).not_to be_nil

      # Check for temperature unit label
      label = modal.at_xpath(".//label[@for='unit-toggle']")
      expect(label.text).to include('Metric units')

      # Check for toggle input with proper association
      toggle = modal.at_xpath(".//input[@id='unit-toggle'][@type='checkbox']")
      expect(toggle).not_to be_nil
      expect(toggle['class']).to include('switch')

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
      expect(toggle['class']).to include('switch')

      # Check for label text
      label = modal.at_xpath(".//label[@for='filter-snow-toggle']")
      expect(label).not_to be_nil
      expect(label.text).to include('Only show resorts with snow')
    end

    it 'includes close button in modal' do
      index_html = File.read(File.join(build_dir, 'index.html'))
      doc        = Nokogiri::HTML(index_html)

      modal        = doc.at_xpath("//dialog[@id='settings_modal']")
      close_button = modal.at_xpath(".//form[@method='dialog']/button[@aria-label='Close']")
      expect(close_button).not_to be_nil
    end

    it 'has native dialog structure' do
      index_html = File.read(File.join(build_dir, 'index.html'))
      doc        = Nokogiri::HTML(index_html)

      modal = doc.at_xpath("//dialog[@id='settings_modal']")
      expect(modal['class']).to include('dialog')
      expect(modal['aria-labelledby']).to eq('settings-title')
      expect(modal.at_xpath(".//div[contains(@class, 'dialog-box')]")).not_to be_nil
    end

    it 'includes settings in all page types' do
      # Check index page
      index_html = File.read(File.join(build_dir, 'index.html'))
      doc        = Nokogiri::HTML(index_html)
      expect(doc.at_xpath("//button[@aria-label='Settings']")).not_to be_nil
      expect(doc.at_xpath("//dialog[@id='settings_modal']")).not_to be_nil

      # Check a country page
      country_files = Dir[File.join(build_dir, 'countries', '*.html')]
      country_html  = File.read(country_files.first)
      country_doc   = Nokogiri::HTML(country_html)
      expect(country_doc.at_xpath("//button[@aria-label='Settings']")).not_to be_nil
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
        country_files = Dir[File.join(build_dir, 'countries', '*.html')]
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
      def resort_docs
        Dir[File.join(build_dir, 'resorts', '*.html')].lazy.map { |f| Nokogiri::HTML(File.read(f)) }
      end

      def sixteen_day_total(doc)
        doc.css('section[aria-labelledby="snow-heading"] dd data').last['value'].to_f
      end

      def og_description(doc)
        doc.at_xpath("//meta[@property='og:description']")['content']
      end

      it 'summarizes 7- and 16-day snow when snow is expected' do
        doc = resort_docs.find { |d| sixteen_day_total(d).positive? }

        expect(og_description(doc)).to match(/\d.* of snow in the next 7 days, \d.* over 16 days\./)
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

      it 'says so when no snow is expected' do
        doc = resort_docs.find { |d| sixteen_day_total(d).zero? }

        expect(og_description(doc)).to include('No snow in the 16-day forecast.')
      end
    end

    describe 'page-specific metadata' do
      it 'includes snow count in country page descriptions' do
        country_files = Dir[File.join(build_dir, 'countries', '*.html')]
        country_file  = country_files.first
        country_html  = File.read(country_file)
        doc           = Nokogiri::HTML(country_html)

        og_description = doc.at_xpath("//meta[@property='og:description']")['content']

        # Should mention resorts with snow
        expect(og_description).to match(/\A\d+ of \d+ ski resorts? in .+ ha(s|ve) snow in the next 7 days/)
      end

      it 'includes snow count in state page descriptions' do
        state_files = Dir[File.join(build_dir, 'states', '*.html')]
        next if state_files.empty? # Skip if no state pages (small country)

        state_file = state_files.first
        state_html = File.read(state_file)
        doc        = Nokogiri::HTML(state_html)

        og_description = doc.at_xpath("//meta[@property='og:description']")['content']

        # Should mention resorts with snow
        expect(og_description).to match(/\A\d+ of \d+ ski resorts? in .+ ha(s|ve) snow in the next 7 days/)
      end

      it 'includes correct URL for about page' do
        about_html = File.read(File.join(build_dir, 'about.html'))
        doc        = Nokogiri::HTML(about_html)

        og_url = doc.at_xpath("//meta[@property='og:url']")['content']
        expect(og_url).to eq('https://whereto.ski/about')
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
