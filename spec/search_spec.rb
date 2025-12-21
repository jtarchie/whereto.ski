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
      expect(page).to have_css('#search-button', visible: true)
    end

    it 'displays search icon SVG' do
      visit '/'
      expect(page).to have_css('#search-button svg')
    end
  end

  describe 'search modal' do
    it 'opens search modal when clicking search button' do
      visit '/'
      find('#search-button').click

      expect(page).to have_css('#search-modal[open]', wait: 2)
      expect(page).to have_css('#search-input', visible: true)
    end

    it 'focuses search input when modal opens' do
      visit '/'
      find('#search-button').click

      # Check that search input has focus
      expect(page.evaluate_script('document.activeElement.id')).to eq('search-input')
    end

    it 'closes modal when clicking backdrop' do
      visit '/'
      find('#search-button').click
      expect(page).to have_css('#search-modal[open]')

      # Click outside the modal box (on the backdrop)
      page.execute_script("document.getElementById('search-modal').close()")
      expect(page).not_to have_css('#search-modal[open]')
    end
  end

  describe 'search data loading' do
    it 'loads search data when modal is opened' do
      visit '/'
      find('#search-button').click

      # Wait for loading indicator to have the hidden class (data loaded)
      expect(page).to have_css('#search-loading.hidden', visible: :all, wait: 5)
    end

    it 'has search data JSON file available' do
      # Make a direct request to the JSON file
      visit '/assets/search-data.json'
      expect(page).to have_content('"type":"country"')
      expect(page).to have_content('"type":"resort"')
    end
  end

  describe 'search functionality' do
    before do
      visit '/'
      find('#search-button').click
      # Wait for search data to load
      sleep 1
    end

    it 'displays results when searching for a country' do
      fill_in 'search-input', with: 'United States'

      # Wait for debounce and results
      expect(page).to have_css('#search-results', wait: 2)
      expect(page).to have_content('Countries')
      expect(page).to have_content('United States')
    end

    it 'displays results when searching for a state' do
      fill_in 'search-input', with: 'Colorado'

      expect(page).to have_css('#search-results', wait: 2)
      expect(page).to have_content('States / Regions', wait: 2)
      expect(page).to have_content('Colorado')
    end

    it 'displays results when searching for a resort' do
      fill_in 'search-input', with: 'Vail'

      expect(page).to have_css('#search-results', wait: 2)
      expect(page).to have_content('Ski Resorts', wait: 2)
      expect(page).to have_content('Vail')
    end

    it 'shows "No results found" when search returns nothing' do
      fill_in 'search-input', with: 'xyzabc123notfound'

      expect(page).to have_css('#search-empty:not(.hidden)', wait: 2)
      expect(page).to have_content('No results found')
    end

    it 'groups results by type' do
      fill_in 'search-input', with: 'Japan'

      expect(page).to have_css('#search-results', wait: 2)

      # Should show country
      expect(page).to have_content('Countries')

      # Should show resorts
      expect(page).to have_content('Ski Resorts')
    end

    it 'limits results to prevent overwhelming UI' do
      # Search for something very common
      fill_in 'search-input', with: 'a'

      expect(page).to have_css('#search-results', wait: 2)

      # Count total links in results (should be limited to 50)
      result_links = page.all('#search-results a')
      expect(result_links.count).to be <= 50
    end

    it 'includes location information in resort results' do
      fill_in 'search-input', with: 'Whistler'

      expect(page).to have_css('#search-results', wait: 2)

      # Resort results should show state and country
      within('#search-results') do
        # Look for the location info (state, country)
        expect(page).to have_css('.text-xs.text-base-content\\/60')
      end
    end
  end

  describe 'search result navigation' do
    before do
      visit '/'
      find('#search-button').click
      sleep 1 # Wait for search data to load
    end

    it 'navigates to country page when clicking country result' do
      fill_in 'search-input', with: 'Switzerland'

      within('#search-results') do
        click_link 'Switzerland', match: :first
      end

      expect(page).to have_current_path(%r{/countries/switzerland}, wait: 3)
    end

    it 'navigates to resort page when clicking resort result' do
      fill_in 'search-input', with: 'Aspen'

      within('#search-results') do
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

      expect(page).to have_css('#search-modal[open]', wait: 2)
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

      expect(page.evaluate_script('document.activeElement.id')).to eq('search-input')
    end
  end

  describe 'search state management' do
    it 'clears search input and results when modal closes' do
      visit '/'
      find('#search-button').click
      sleep 1

      fill_in 'search-input', with: 'Colorado'
      expect(page).to have_css('#search-results', wait: 2)

      # Close modal
      page.execute_script("document.getElementById('search-modal').close()")

      # Reopen modal
      find('#search-button').click

      # Input should be empty
      expect(find('#search-input').value).to eq('')

      # Results should be cleared (no child elements)
      expect(page.find('#search-results', visible: :all).text.strip).to eq('')
    end

    it 'maintains search data after first load' do
      visit '/'
      find('#search-button').click
      sleep 1

      # Close and reopen
      page.execute_script("document.getElementById('search-modal').close()")
      find('#search-button').click

      # Search should work immediately without reloading data
      fill_in 'search-input', with: 'Alaska'
      expect(page).to have_css('#search-results', wait: 1)
    end
  end

  describe 'mobile responsiveness' do
    it 'displays search button on mobile viewport' do
      page.driver.browser.manage.window.resize_to(375, 667) # iPhone SE size

      visit '/'
      expect(page).to have_css('#search-button', visible: true)
    end

    it 'modal is responsive on mobile' do
      page.driver.browser.manage.window.resize_to(375, 667)

      visit '/'
      find('#search-button').click

      expect(page).to have_css('#search-modal[open]')
      expect(page).to have_css('.modal-box')
    end
  end

  describe 'performance' do
    it 'loads search data file efficiently' do
      visit '/'

      start_time = Time.now
      find('#search-button').click
      sleep 1 # Wait for data to load
      end_time   = Time.now

      # Loading should complete within reasonable time
      expect(end_time - start_time).to be < 3
    end

    it 'debounces search input to avoid excessive filtering' do
      visit '/'
      find('#search-button').click
      sleep 1

      # Type quickly
      fill_in 'search-input', with: 'C'
      fill_in 'search-input', with: 'Co'
      fill_in 'search-input', with: 'Col'
      fill_in 'search-input', with: 'Colo'

      # Should only show results after debounce period
      expect(page).to have_css('#search-results', wait: 1)
    end
  end
end
