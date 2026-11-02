# frozen_string_literal: true

require 'spec_helper'
require 'rack'

RSpec.describe('Near me', :js, type: :feature) do
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

  before do
    visit '/states/colorado'
    execute_script('localStorage.clear()')
    visit '/states/colorado'
  end

  def locate(lat: nil, lon: nil, error: nil)
    outcome = error ? "fail({ code: #{error}, PERMISSION_DENIED: 1 })" : "ok({ coords: { latitude: #{lat}, longitude: #{lon} } })"
    execute_script(<<~JS)
      Object.defineProperty(navigator, 'geolocation', {
        configurable: true,
        value: { getCurrentPosition: (ok, fail) => #{outcome} },
      });
    JS
  end

  def chip
    find('button[data-near-me]')
  end

  def snow_values
    all('#near-me tbody tr').map { |row| row.all('data[data-k="s"]').first&.[]('value').to_f }
  end

  it 'ranks resorts within 300 km by 7-day snow, and toggles back to the page list' do
    locate(lat: 40.455, lon: -106.804)
    chip.click

    expect(page).to have_css('#near-me h2', text: 'Near you')
    expect(chip['aria-pressed']).to eq('true')
    expect(page).to have_no_css('[data-ranked-section]')
    expect(all('#near-me tbody tr').length).to be_between(1, 25)
    expect(snow_values).to eq(snow_values.sort.reverse)
    expect(page).to have_css('#near-me tbody data[data-k="d"]', minimum: 1)

    chip.click
    expect(page).to have_css('[data-ranked-section]')
    expect(page).to have_no_css('#near-me', visible: true)
  end

  it 'hides the chip for good when permission is denied' do
    locate(error: 1)
    chip.click

    expect(page).to have_no_css('button[data-near-me]')
    visit '/states/colorado'
    expect(page).to have_no_css('button[data-near-me]')
  end

  it 'keeps the chip and says so when location is unavailable' do
    locate(error: 2)
    chip.click

    expect(page).to have_content("Couldn't find your location. Try again.")
    expect(page).to have_css('button[data-near-me]')
    expect(page).to have_css('[data-ranked-section]')
  end

  it 'says so when there are no resorts nearby' do
    locate(lat: 0, lon: -140)
    chip.click

    expect(page).to have_content(/No resorts within \d+ (mi|km) of you/)
  end

  it 'lists the nearest resorts when none nearby has snow' do
    execute_script(<<~JS)
      const index = { cl: ['Nowhere'], d: [{ t: 'r', n: 'Dry Hill', c: 0, s: 'Flat', u: '/x', l: [10, 10] }] };
      window.fetch = () => Promise.resolve(new Response(JSON.stringify(index)));
    JS
    locate(lat: 10.1, lon: 10.1)
    chip.click

    expect(page).to have_content('No snow forecast in the next 7 days within')
    expect(page).to have_css('#near-me tbody tr', text: 'Dry Hill')
  end

  it 'still initializes when ?sort= is not a valid selector fragment' do
    visit '/states/colorado?sort=%22%5D'

    expect(page).to have_css('button[data-near-me]')
    expect(page).to have_css('[data-ranked-section] table')
  end
end
