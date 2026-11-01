# frozen_string_literal: true

require 'spec_helper'
require 'rack'
require 'nokogiri'
require 'zlib'

RSpec.describe('Map', :js, type: :feature) do
  let(:build_dir) { @build_dir }

  before(:all) do
    stub_weather_api
    SharedBuild.perform!
    @build_dir      = SharedBuild.build_dir
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

  def placeholder(*path)
    Nokogiri::HTML(File.read(File.join(build_dir, *path))).at_css('[data-map]')
  end

  it 'scopes the overview to the page and the locator to the resort' do
    expect(placeholder('index.html').to_h).to include('data-map' => 'overview', 'data-country' => '', 'data-region' => '')
    expect(placeholder('countries', 'united-states-of-america.html')['data-country']).to eq('United States of America')
    expect(placeholder('states', 'colorado.html').to_h).to include('data-country' => 'United States of America', 'data-region' => 'Colorado')

    locator = placeholder('resorts', 'steamboat-ski-resort.html')
    expect(locator.to_h).to include('data-map' => 'locator', 'data-url' => '/resorts/steamboat-ski-resort')
    expect(locator['data-lat'].to_f).to be_within(0.01).of(40.455)
  end

  it 'reserves the map height before anything loads' do
    expect(placeholder('index.html')['class']).to include('h-(--size-map)')
  end

  it 'loads MapLibre only once the map scrolls into view' do
    visit '/'
    expect(page).to have_no_css('script[src="/assets/map.js"]', visible: :all)

    execute_script("document.querySelector('[data-map]').scrollIntoView()")
    expect(page).to have_css('script[src="/assets/map.js"]', visible: :all)
    expect(page).to have_css('link[href="/assets/maplibre/maplibre-gl.css"]', visible: :all)
  end

  it 'keeps the core script within 10 KB gzipped' do
    main = File.read(File.join(build_dir, 'assets', 'main.js'))

    expect(Zlib.gzip(main).bytesize).to be <= 10_000
  end
end
