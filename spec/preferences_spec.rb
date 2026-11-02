# frozen_string_literal: true

require 'spec_helper'
require 'rack'
require 'tmpdir'

RSpec.describe('Unit and timezone preferences', :js, type: :feature) do
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
    visit '/resorts/steamboat-ski-resort'
    execute_script('localStorage.clear()')
    visit '/resorts/steamboat-ski-resort'
  end

  def first_text(selector)
    find(selector, match: :first, visible: :all).text(:all)
  end

  it 'defaults to imperial for en-US browsers' do
    expect(first_text('data[data-k="t"]')).to end_with('°F')
    expect(first_text('data[data-k="s"]')).to end_with('″')
  end

  it 'switches units live and remembers the choice' do
    find('button[aria-label="Settings"]').click
    find('label[for="unit-toggle"]').click

    expect(first_text('data[data-k="t"]')).to end_with('°C')
    expect(first_text('data[data-k="w"]')).to end_with('km/h')

    visit '/resorts/steamboat-ski-resort'
    expect(first_text('data[data-k="t"]')).to end_with('°C')
  end

  it 'shows hourly times in the chosen zone' do
    find('button[aria-label="Settings"]').click
    select 'Asia/Tokyo', from: 'tz-select'
    expect(first_text('time[data-k="dh"]')).to match(/\AWed,? 3 AM\z/)
    expect(first_text('[data-tz-label]')).to eq('GMT+9')

    select 'Resort local', from: 'tz-select'
    expect(first_text('time[data-k="dh"]')).to match(/\ATue,? 12 PM\z/)
  end

  it 'keeps working when storage throws' do
    browser = page.driver.browser
    hook    = browser.execute_cdp(
      'Page.addScriptToEvaluateOnNewDocument',
      source: <<~JS
        Storage.prototype.getItem = () => { throw new DOMException('blocked', 'SecurityError') };
        Storage.prototype.setItem = () => { throw new DOMException('blocked', 'SecurityError') };
      JS
    )
    begin
      visit '/states/colorado'

      expect(page).to have_css('button[data-near-me]')
      expect(first_text('data[data-k="s"]')).to end_with('″')
      find('button[aria-label="Settings"]').click
      find('label[for="unit-toggle"]').click
      expect(first_text('data[data-k="s"]')).to end_with('cm')
      page.send_keys(:escape)
      expect(page).to have_no_css('dialog[open]')
      find('button[aria-label="Search"]').click
      expect(page).to have_css('dialog#search-modal[open]')
    ensure
      browser.execute_cdp('Page.removeScriptToEvaluateOnNewDocument', identifier: hook['identifier'])
    end
  end
end
