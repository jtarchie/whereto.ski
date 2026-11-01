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

  it 'no longer shows the Best Days score' do
    expect(doc.text).not_to include('Best Days')
  end

  it 'links breadcrumbs through region for large countries only' do
    expect(doc.css('nav[aria-label="Breadcrumb"] a').map(&:text)).to eq(['World', 'United States of America', 'Colorado'])

    small = page_for('ski-pista-bigell-dardhe') # Albania: one resort, no region pages
    expect(small.css('nav[aria-label="Breadcrumb"] a').length).to eq(2)
  end
end
