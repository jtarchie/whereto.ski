# frozen_string_literal: true

require 'spec_helper'
require 'rack'
require 'json'

RSpec.describe('Search', :js, type: :feature) do
  let(:build_dir) { @build_dir }

  before(:all) do
    stub_weather_api
    @build_dir = serve_shared_build!
  end

  def open_search
    visit '/'
    find('button[aria-label="Search"]').click
    expect(page).to have_css('dialog#search-modal[open]')
  end

  def results
    find_by_id('search-results')
  end

  describe 'index' do
    let(:index) { JSON.parse(File.read(File.join(build_dir, 'assets', 'search-data.json'))) }

    it 'carries location and 7-day snow for resorts' do
      steamboat = index['d'].find { |item| item['u'] == '/resorts/steamboat-ski-resort' }

      expect(steamboat['l']).to eq([40.455, -106.804])
      expect(index['d'].count { |item| item['t'] == 'r' && item['w'] }).to be > 100
      expect(index['d'].select { |item| item['w'] }.map { |item| item['w'] }).to all(be_positive)
    end
  end

  it 'opens with the button, Cmd/Ctrl+K and /, focusing the field' do
    open_search
    expect(page).to have_css('#search-input:focus')

    page.send_keys(:escape)
    find('body').send_keys('/')
    expect(page).to have_css('dialog#search-modal[open] #search-input:focus')

    page.send_keys(:escape)
    find('body').send_keys([:control, 'k'])
    expect(page).to have_css('dialog#search-modal[open]')
  end

  it 'lets / be typed inside a field' do
    open_search
    fill_in 'search-input', with: 'a/b'

    expect(find_by_id('search-input').value).to eq('a/b')
  end

  it 'groups results, ranks name matches first and shows 7-day snow on resorts' do
    open_search
    fill_in 'search-input', with: 'Colorado'

    within(results) do
      expect(page).to have_css('h3', text: /regions/i)
      expect(first('section a')).to have_text('Colorado')
    end

    fill_in 'search-input', with: 'Steamboat'
    within(results) do
      link = find('a[href="/resorts/steamboat-ski-resort"]')
      expect(link).to have_text('Colorado · United States of America')
      expect(link).to have_css('data[title="Next 7 days"]')
    end
  end

  it 'renders OpenStreetMap names as text, never markup' do
    visit '/'
    execute_script(<<~JS)
      const index = { cl: ['Nowhere'], d: [{ t: 'r', n: '<img src=x onerror="window.pwned=1">Evil', c: 0, s: 'R', u: '/x', w: 3 }] };
      window.fetch = () => Promise.resolve(new Response(JSON.stringify(index)));
    JS
    find('button[aria-label="Search"]').click
    fill_in 'search-input', with: 'Evil'

    within(results) { expect(page).to have_text('<img src=x onerror="window.pwned=1">Evil') }
    expect(results).to have_no_css('img')
    expect(evaluate_script('window.pwned')).to be_nil
  end

  it 'says so when nothing matches' do
    open_search
    fill_in 'search-input', with: 'xyzabc123notfound'

    expect(page).to have_content('No matches. Try a town or region name.')
  end

  it 'caps results at 50' do
    open_search
    fill_in 'search-input', with: 'a'

    within(results) { expect(page).to have_css('a', minimum: 1) }
    expect(results.all('a').length).to be <= 50
  end

  it 'navigates to the result' do
    open_search
    fill_in 'search-input', with: 'Steamboat'
    within(results) { click_on 'Steamboat Ski Resort' }

    expect(page).to have_current_path('/resorts/steamboat-ski-resort')
  end

  it 'clears the query and results on close' do
    open_search
    fill_in 'search-input', with: 'Vail'
    within(results) { expect(page).to have_link('Vail') }

    find('#search-modal button[aria-label="Close"]').click
    find('button[aria-label="Search"]').click

    expect(find_by_id('search-input').value).to eq('')
    expect(page).to have_no_css('#search-results a')
  end

  it 'drops a pending search when the dialog closes' do
    open_search
    fill_in 'search-input', with: 'Vail'
    within(results) { expect(page).to have_link('Vail') }

    # Type and close in one tick so the debounce is still pending; a later
    # timer (queued after the 300ms one) flags that the delay has elapsed.
    execute_script(<<~JS)
      const input = document.getElementById('search-input');
      input.value = 'Steamboat';
      input.dispatchEvent(new Event('input', { bubbles: true }));
      document.getElementById('search-modal').close();
      setTimeout(() => { document.documentElement.dataset.debounced = '1' }, 400);
    JS
    expect(page).to have_css('html[data-debounced]', visible: :all)

    expect(page).to have_no_css('#search-results a', visible: :all)
  end

  it 'shows an error when the index cannot load, and retries on the next open' do
    visit '/'
    execute_script(<<~JS)
      window.__fetch = window.fetch;
      window.fetch = () => Promise.reject(new Error('offline'));
    JS
    find('button[aria-label="Search"]').click
    expect(page).to have_css('#search-error', text: "Search couldn't load")

    page.send_keys(:escape)
    execute_script('window.fetch = window.__fetch')
    find('button[aria-label="Search"]').click
    fill_in 'search-input', with: 'Vail'

    expect(page).to have_no_css('#search-error')
    within(results) { expect(page).to have_link('Vail') }
  end
end
