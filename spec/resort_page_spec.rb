# frozen_string_literal: true

require 'spec_helper'
require 'nokogiri'

RSpec.describe('Resort page', type: :feature) do
  before(:all) do
    stub_weather_api
    SharedBuild.perform!
  end

  def page_for(slug)
    Nokogiri::HTML(File.read(File.join(SharedBuild.build_dir, 'resorts', "#{slug}.html")))
  end

  let(:doc) { page_for('steamboat-ski-resort') }

  it 'leads with the four snow totals' do
    labels = doc.css('section[aria-labelledby="snow-heading"] dt').map { |dt| dt.text.strip }
    values = doc.css('section[aria-labelledby="snow-heading"] dd data[data-k="s"]').map { |d| d['value'].to_f }

    expect(labels).to eq(['Past 72h', 'Next 24h', 'Next 7 days', '16 days'])
    expect(values.length).to eq(4)
    expect(values[2]).to be <= values[3]
  end

  it 'shows a 16-day strip and calls out a day only when one reaches 2 inches' do
    days    = doc.css('section[aria-labelledby="strip-heading"] li')
    biggest = days.map { |li| li.at_css('data')&.[]('value').to_f }.max
    callout = doc.at_css('section[aria-labelledby="snow-heading"] strong')&.text

    expect(days.length).to eq(16)
    expect(callout.nil?).to eq(biggest < 2)
  end

  it 'covers the next three days of snow or rain' do
    expect(doc.css('section[aria-labelledby="outlook-heading"] li').length).to eq(3)
  end

  it 'lists nearby resorts ranked by 7-day snow' do
    snow = doc.css('section[aria-labelledby="nearby-heading"] li data[data-k="s"]').map { |d| d['value'].to_f }

    expect(snow.length).to be_between(1, 8)
    expect(snow).to eq(snow.sort.reverse)
  end

  it 'only suggests a nearby resort with double the snow and 3 inches more' do
    suggestions = Dir[File.join(SharedBuild.build_dir, 'resorts', '*.html')].first(300).filter_map do |file|
      page   = Nokogiri::HTML(File.read(file))
      mine   = page.css('section[aria-labelledby="snow-heading"] dd data')[2]['value'].to_f
      better = page.xpath('//p[contains(., "More snow nearby")]//data[@data-k="s"]').first
      [mine, better['value'].to_f] if better
    end

    expect(suggestions).not_to be_empty
    suggestions.each { |mine, theirs| expect(theirs).to be >= [mine * 2, mine + 3].max }
  end

  it 'shows terrain from OpenSkiMap' do
    terrain = doc.at_css('section[aria-labelledby="terrain-heading"]').text.squish

    expect(terrain).to include('Runs · 199', 'Advanced 80', 'Lifts · 20', 'Chair lift 15', 'www.steamboat.com')
  end

  it 'puts 48 hours and 16 days behind details, hours in the viewer time zone' do
    hourly, daily = doc.css('details')

    expect(hourly.css('tbody tr').length).to eq(48)
    expect(hourly.css('tbody time[data-k="dh"]').length).to eq(48)
    expect(hourly.css('thead th').length).to eq(6)
    expect(daily.css('tbody tr').length).to eq(16)
  end

  it 'no longer shows the Best Days score' do
    expect(doc.text).not_to include('Best Days')
  end

  it 'links breadcrumbs through region for large countries only' do
    expect(doc.css('nav[aria-label="Breadcrumb"] a').map(&:text)).to eq(['World', 'United States of America', 'Colorado'])

    small = page_for('ski-pista-bigell-dardhe') # Albania: one resort, no region pages
    expect(small.css('nav[aria-label="Breadcrumb"] a').length).to eq(2)
  end
end
