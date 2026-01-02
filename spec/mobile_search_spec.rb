# frozen_string_literal: true

require 'spec_helper'
require 'rack'
require 'tmpdir'

RSpec.describe('Mobile Search Feature', :js, type: :feature) do
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

  describe 'mobile viewport search' do
    before do
      # Set mobile viewport size
      page.driver.browser.manage.window.resize_to(375, 667)
    end

    after do
      # Reset to desktop size
      page.driver.browser.manage.window.resize_to(1400, 900)
    end

    it 'uses modal-top class on mobile for better keyboard handling' do
      visit '/'

      # Check that modal has modal-top class (use visible: false since dialog is hidden)
      modal = find('#search-modal', visible: false)
      expect(modal['class']).to include('modal-top')
    end

    it 'opens search modal on mobile' do
      visit '/'
      find('button[aria-label="Search"]').click

      expect(page).to have_css('dialog[open]', wait: 2)
      expect(page).to have_field('search-input', visible: true)
    end

    it 'search input has enterkeyhint for mobile keyboard' do
      visit '/'

      # Check for enterkeyhint attribute which helps mobile keyboards
      search_input = find('#search-input', visible: false)
      expect(search_input['enterkeyhint']).to eq('search')
    end

    it 'search results are scrollable on mobile' do
      visit '/'
      find('button[aria-label="Search"]').click
      sleep 1 # Wait for data to load

      fill_in 'search-input', with: 'a'

      # Wait for results and check scrollability
      expect(page).to have_css('#search-results', wait: 2)

      # Results container should have overflow-y-auto
      results_container = find('#search-results')
      expect(results_container['class']).to include('overflow-y-auto')
    end

    it 'modal box uses dvh units for mobile viewport' do
      visit '/'
      find('button[aria-label="Search"]').click

      modal_box = find('.modal-box')
      # Check for responsive classes
      expect(modal_box['class']).to match(/max-h-\[.*dvh\]|sm:max-h/)
    end

    it 'search still functions correctly on mobile viewport' do
      visit '/'
      find('button[aria-label="Search"]').click
      sleep 1

      fill_in 'search-input', with: 'Colorado'

      expect(page).to have_link('Colorado', wait: 2)
    end

    it 'can close modal with close button on mobile' do
      visit '/'
      find('button[aria-label="Search"]').click

      expect(page).to have_css('dialog[open]')

      # Click the X button
      within('dialog[open]') do
        find('button.btn-circle').click
      end

      expect(page).not_to have_css('dialog[open]')
    end
  end

  describe 'modal CSS classes' do
    it 'has modal-top sm:modal-middle for responsive positioning' do
      visit '/'
      modal = find('#search-modal', visible: false)
      expect(modal['class']).to include('modal-top')
      expect(modal['class']).to include('sm:modal-middle')
    end

    it 'modal box has responsive width classes' do
      visit '/'
      find('button[aria-label="Search"]').click

      modal_box = find('.modal-box')
      expect(modal_box['class']).to include('w-full')
      expect(modal_box['class']).to include('sm:w-11/12')
    end
  end
end
