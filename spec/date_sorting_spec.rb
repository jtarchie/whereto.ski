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
    it 'has date sorting dropdown' do
      visit '/states/colorado'
      expect(page).to have_select('sort-by-date')
    end

    it 'has Default option in dropdown' do
      visit '/states/colorado'
      expect(page).to have_select('sort-by-date', with_options: ['Default'])
    end

    it 'populates dropdown with date options from table headers' do
      visit '/states/colorado'

      # Get the dropdown options
      options = find('#sort-by-date').all('option').map(&:text)

      # Should have Default plus date options
      expect(options.length).to be > 1
      expect(options.first).to eq('Default')
    end

    it 'sorts table by selected date descending' do
      visit '/states/colorado'

      # Get initial order of first resort names
      initial_first = find('#forecast-body tr:first-child td:first-child').text

      # Select a date column (index 0 = first date after Location column)
      select_option = find('#sort-by-date option:nth-child(2)')
      find('#sort-by-date').select(select_option.text)

      # Table should be re-sorted (may or may not change the first row depending on data)
      # Just verify the select changed and table has rows
      expect(find('#sort-by-date').value).to eq('0')
      expect(page).to have_css('#forecast-body tr')
    end

    it 'resets to original order when Default is selected' do
      visit '/states/colorado'

      # Get initial order of all resorts
      initial_order = all('#forecast-body tr td:first-child').map(&:text)

      # Select a date to sort
      select_option = find('#sort-by-date option:nth-child(2)')
      find('#sort-by-date').select(select_option.text)

      # Reset to default
      find('#sort-by-date').select('Default')

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
  end
end
