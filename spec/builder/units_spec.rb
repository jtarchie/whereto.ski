# frozen_string_literal: true

require 'spec_helper'

RSpec.describe FollowTheSnow::Builder::Units do
  subject(:units) { Class.new { include FollowTheSnow::Builder::Units }.new }

  it 'renders raw imperial values with an imperial default' do
    expect(units.temp_value(28.6)).to eq('<data value="28.6" data-k="t">29°F</data>')
    expect(units.speed_value(12.34)).to eq('<data value="12.3" data-k="w">12 mph</data>')
    expect(units.height_value(10_523.4)).to eq('<data value="10523" data-k="h">10,523 ft</data>')
    expect(units.distance_value(100.0)).to eq('<data value="100.0" data-k="d">62 mi</data>')
  end

  it 'uses a dash for missing values' do
    expect([units.temp_value(nil), units.speed_value(nil), units.height_value(nil)]).to all(eq('–'))
  end

  it 'emits UTC instants with resort-local default text' do
    time = Time.new(2023, 3, 14, 12, 0, 0, -21_600)
    expect(units.time_value(time)).to eq('<time datetime="2023-03-14T18:00:00Z" data-k="hr">12 PM</time>')
    expect(time.utc_offset).to eq(-21_600)
  end

  it 'buckets snow into the token scale' do
    expect([0, 0.4, 1, 2, 6, 12].map { |i| units.snow_level(i) }).to eq([0, 1, 2, 3, 4, 5])
  end
end
