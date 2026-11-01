# frozen_string_literal: true

require 'spec_helper'
require 'rack'

RSpec.describe('Keyboard access', :js, type: :feature) do
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

  def focused
    evaluate_script('document.activeElement.id || document.activeElement.getAttribute("aria-label") || document.activeElement.textContent.trim()')
  end

  def tabbed_to?(max: 80)
    max.times do
      page.send_keys(:tab)
      return true if yield
    end
    false
  end

  it 'returns focus to the opener when a dialog closes' do
    visit '/'
    find('button[aria-label="Settings"]').click
    expect(page).to have_css('#settings_modal[open]')
    page.send_keys(:escape)
    expect(focused).to eq('Settings')

    find('#search-button').click
    page.send_keys(:escape)
    expect(focused).to eq('search-button')
  end

  it 'storm chaser: sorts the region list and opens the top resort without a mouse' do
    visit '/states/colorado'
    expect(tabbed_to? { evaluate_script('document.activeElement.dataset.sort') == '24h' }).to be(true)
    page.send_keys(:enter)
    expect(page).to have_current_path('/states/colorado?sort=24h')

    expect(tabbed_to? { evaluate_script('!!document.activeElement.closest("[data-ranked] tbody")') }).to be(true)
    page.send_keys(:enter)
    expect(page).to have_current_path(%r{/resorts/})
  end

  it 'lookup: finds a resort with / and opens it from the keyboard' do
    visit '/'
    find('body').send_keys('/')
    page.send_keys('Steamboat')
    expect(page).to have_css('#search-results a[href="/resorts/steamboat-ski-resort"]')

    expect(tabbed_to?(max: 10) { evaluate_script('document.activeElement.getAttribute("href")') == '/resorts/steamboat-ski-resort' }).to be(true)
    page.send_keys(:enter)
    expect(page).to have_current_path('/resorts/steamboat-ski-resort')

    expect(tabbed_to? { evaluate_script('document.activeElement.tagName') == 'SUMMARY' }).to be(true)
    page.send_keys(:enter)
    expect(page).to have_css('details[open] tbody tr', minimum: 48)
  end
end
