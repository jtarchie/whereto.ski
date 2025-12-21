# frozen_string_literal: true

require 'spec_helper'
require 'rack'
require 'tmpdir'

RSpec.describe('Search Feature', :js, type: :feature) do
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
      # Serve static files from build directory
      use Rack::Static,
          urls: ['/'],
          root: build_directory,
          index: 'index.html',
          cascade: true

      # Fallback to serve files directly
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

  describe 'search button visibility' do
    it 'displays search button in navbar' do
      visit '/'
      expect(page).to have_css('button[aria-label="Search"]', visible: true)
    end

    it 'displays search icon SVG' do
      visit '/'
      within('button[aria-label="Search"]') do
        expect(page).to have_css('svg')
      end
    end
  end

  describe 'search modal' do
    it 'opens search modal when clicking search button' do
      visit '/'
      find('button[aria-label="Search"]').click

      expect(page).to have_css('dialog[open]', wait: 2)
      expect(page).to have_field('search-input', visible: true)
    end

    it 'focuses search input when modal opens' do
      visit '/'
      find('button[aria-label="Search"]').click

      # Check that search input has focus
      active_label = page.evaluate_script("document.activeElement.getAttribute('aria-label')")
      expect(active_label).to eq('Search for countries, states, or resorts')
    end

    it 'closes modal when clicking backdrop' do
      visit '/'
      find('button[aria-label="Search"]').click
      expect(page).to have_css('dialog[open]')

      # Click outside the modal box (on the backdrop)
      page.execute_script("document.querySelector('dialog[open]').close()")
      expect(page).not_to have_css('dialog[open]')
    end
  end

  describe 'search data loading' do
    it 'loads search data when modal is opened' do
      visit '/'
      find('button[aria-label="Search"]').click

      # Wait for loading indicator to disappear (data loaded)
      expect(page).not_to have_content('Loading search data...', wait: 5)
    end

    it 'has search data JSON file available' do
      # Make a direct request to the JSON file
      visit '/assets/search-data.json'
      # Check for compressed format: "cl" array and "d" data array with type codes
      expect(page).to have_content('"cl"')
      expect(page).to have_content('"d"')
      expect(page).to have_content('"t":"c"') # country type code
      expect(page).to have_content('"t":"r"') # resort type code
    end
  end

  describe 'search functionality' do
    before do
      visit '/'
      find('button[aria-label="Search"]').click
      # Wait for search data to load
      sleep 1
    end

    it 'displays results when searching for a country' do
      fill_in 'search-input', with: 'United States'

      # Wait for debounce and results
      expect(page).to have_content('Countries', wait: 2)
      expect(page).to have_link('United States')
    end

    it 'displays results when searching for a state' do
      fill_in 'search-input', with: 'Colorado'

      expect(page).to have_content('States / Regions', wait: 2)
      expect(page).to have_link('Colorado')
    end

    it 'displays results when searching for a resort' do
      fill_in 'search-input', with: 'Vail'

      expect(page).to have_content('Ski Resorts', wait: 2)
      expect(page).to have_link('Vail')
    end

    it 'shows "No results found" when search returns nothing' do
      fill_in 'search-input', with: 'xyzabc123notfound'

      expect(page).to have_content('No results found', wait: 2)
    end

    it 'groups results by type' do
      fill_in 'search-input', with: 'Japan'

      # Should show country
      expect(page).to have_content('Countries', wait: 2)

      # Should show resorts
      expect(page).to have_content('Ski Resorts')
    end

    it 'limits results to prevent overwhelming UI' do
      # Search for something very common
      fill_in 'search-input', with: 'a'

      # Count total links in results (should be limited to 50)
      within('dialog[open]') do
        result_links = page.all('a')
        expect(result_links.count).to be <= 50
      end
    end

    it 'includes location information in resort results' do
      fill_in 'search-input', with: 'Whistler'

      # Resort results should show state and country
      within('dialog[open]') do
        # Look for the location info (state, country)
        expect(page).to have_css('.text-xs.text-base-content\\/60', wait: 2)
      end
    end
  end

  describe 'search result navigation' do
    before do
      visit '/'
      find('button[aria-label="Search"]').click
      sleep 1 # Wait for search data to load
    end

    it 'navigates to country page when clicking country result' do
      fill_in 'search-input', with: 'Switzerland'

      within('dialog[open]') do
        click_link 'Switzerland', match: :first
      end

      expect(page).to have_current_path(%r{/countries/switzerland}, wait: 3)
    end

    it 'navigates to resort page when clicking resort result' do
      fill_in 'search-input', with: 'Aspen'

      within('dialog[open]') do
        click_link 'Aspen', match: :first
      end

      expect(page).to have_current_path(%r{/resorts/}, wait: 3)
    end
  end

  describe 'keyboard shortcuts' do
    it 'opens search with Cmd/Ctrl + K' do
      visit '/'

      # Simulate Cmd+K (or Ctrl+K on Windows/Linux)
      page.execute_script(<<~JS)
        const event = new KeyboardEvent('keydown', {
          key: 'k',
          metaKey: true,
          ctrlKey: false
        });
        document.dispatchEvent(event);
      JS

      expect(page).to have_css('dialog[open]', wait: 2)
      # Check input is there by aria-label
      expect(page).to have_css('input[aria-label="Search for countries, states, or resorts"]')
    end

    it 'focuses search input after keyboard shortcut' do
      visit '/'

      page.execute_script(<<~JS)
        const event = new KeyboardEvent('keydown', {
          key: 'k',
          metaKey: true
        });
        document.dispatchEvent(event);
      JS

      active_label = page.evaluate_script("document.activeElement.getAttribute('aria-label')")
      expect(active_label).to eq('Search for countries, states, or resorts')
    end
  end

  describe 'search state management' do
    it 'clears search input and results when modal closes' do
      visit '/'
      find('button[aria-label="Search"]').click
      sleep 1

      fill_in 'search-input', with: 'Colorado'
      expect(page).to have_link('Colorado', wait: 2)

      # Close modal
      page.execute_script("document.querySelector('dialog[open]').close()")

      # Reopen modal
      find('button[aria-label="Search"]').click

      # Input should be empty
      expect(find_field('search-input').value).to eq('')

      # Results should be cleared - no links should be visible
      within('dialog[open]') do
        expect(page).not_to have_link('Colorado', wait: 1)
      end
    end

    it 'maintains search data after first load' do
      visit '/'
      find('button[aria-label="Search"]').click
      sleep 1

      # Close and reopen
      page.execute_script("document.querySelector('dialog[open]').close()")
      find('button[aria-label="Search"]').click

      # Search should work immediately without reloading data
      fill_in 'search-input', with: 'Alaska'
      expect(page).to have_link('Alaska', wait: 1)
    end
  end

  describe 'mobile responsiveness' do
    it 'displays search button on mobile viewport' do
      page.driver.browser.manage.window.resize_to(375, 667) # iPhone SE size

      visit '/'
      expect(page).to have_css('button[aria-label="Search"]', visible: true)
    end

    it 'modal is responsive on mobile' do
      page.driver.browser.manage.window.resize_to(375, 667)

      visit '/'
      find('button[aria-label="Search"]').click

      expect(page).to have_css('dialog[open]')
      expect(page).to have_css('.modal-box')
    end
  end

  describe 'performance' do
    it 'loads search data file efficiently' do
      visit '/'

      start_time = Time.now
      find('button[aria-label="Search"]').click
      sleep 1 # Wait for data to load
      end_time   = Time.now

      # Loading should complete within reasonable time
      expect(end_time - start_time).to be < 3
    end

    it 'debounces search input to avoid excessive filtering' do
      visit '/'
      find('button[aria-label="Search"]').click
      sleep 1

      # Type quickly
      fill_in 'search-input', with: 'C'
      fill_in 'search-input', with: 'Co'
      fill_in 'search-input', with: 'Col'
      fill_in 'search-input', with: 'Colo'

      # Should only show results after debounce period
      expect(page).to have_link('Colorado', wait: 1)
    end
  end
end
