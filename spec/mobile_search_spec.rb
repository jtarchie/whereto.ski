# frozen_string_literal: true

require 'spec_helper'
require 'rack'
require 'tmpdir'

RSpec.describe('Mobile Search Feature', :js, type: :feature) do
  let(:build_dir) { @build_dir }

  before(:all) do
    stub_weather_api
    @build_dir = serve_shared_build!
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

    it 'pins the dialog to the top on mobile so the keyboard does not cover it' do
      visit '/'
      find('button[aria-label="Search"]').click

      top = evaluate_script("document.getElementById('search-modal').getBoundingClientRect().top")
      expect(top).to be < 20
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
      fill_in 'search-input', with: 'a'

      within('#search-results') { expect(page).to have_css('a', minimum: 10) }
      overflow = evaluate_script("getComputedStyle(document.getElementById('search-results')).overflowY")
      expect(overflow).to eq('auto')
      bottom   = evaluate_script("document.getElementById('search-modal').getBoundingClientRect().bottom")
      expect(bottom).to be <= evaluate_script('window.innerHeight')
    end

    it 'fits the dialog within the viewport' do
      visit '/'
      find('button[aria-label="Search"]').click

      bottom = evaluate_script("document.getElementById('search-modal').getBoundingClientRect().bottom")
      expect(bottom).to be <= evaluate_script('window.innerHeight')
    end

    it 'search still functions correctly on mobile viewport' do
      visit '/'
      find('button[aria-label="Search"]').click
      fill_in 'search-input', with: 'Colorado'

      expect(page).to have_link('Colorado', wait: 2)
    end

    it 'can close modal with close button on mobile' do
      visit '/'
      find('button[aria-label="Search"]').click

      expect(page).to have_css('dialog[open]')

      # Click the X button
      within('dialog[open]') do
        find('button[aria-label="Close"]').click
      end

      expect(page).not_to have_css('dialog[open]')
    end
  end
end
