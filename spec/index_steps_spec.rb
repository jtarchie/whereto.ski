# frozen_string_literal: true

require 'spec_helper'
require 'rack'

# The client must take snow level bounds from the search index, never from a literal.
RSpec.describe('Search index steps', :js, type: :feature) do
  before(:all) do
    stub_weather_api
    serve_shared_build!
  end

  # Serves the real index with `mutate` applied (JS body over `index`), before the page fetches it.
  def serve_index(mutate)
    visit '/'
    execute_script(<<~JS)
      const real = window.fetch.bind(window);
      window.fetch = (url) => real(url).then((r) => r.json()).then((index) => {
        #{mutate}
        return new Response(JSON.stringify(index));
      });
    JS
    find('button[aria-label="Search"]').click
    fill_in 'search-input', with: 'Steamboat'
  end

  def steamboat_snow
    find('#search-results a[href="/resorts/steamboat-ski-resort"] data[title="Next 7 days"]')
  end

  it 'colours resorts by the steps in the index (huge bounds: lowest level)' do
    serve_index('index.steps = [1000, 2000, 3000, 4000];')
    expect(steamboat_snow[:class]).to include('bg-snow-1')
  end

  it 'colours resorts by the steps in the index (tiny bounds: highest level)' do
    serve_index('index.steps = [0.001, 0.002, 0.003, 0.004];')
    expect(steamboat_snow[:class]).to include('bg-snow-5')
  end

  it 'reports the search as unavailable when the index has no steps' do
    serve_index('delete index.steps;')
    expect(page).to have_css('#search-error', visible: :visible)
    expect(page).to have_no_css('#search-results a')
  end
end
