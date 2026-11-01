# frozen_string_literal: true

require 'spec_helper'

RSpec.describe(FollowTheSnow::Builder::Context) do
  let(:resort_with_snow) do
    FollowTheSnow::Resort.new(
      id: 1,
      name: 'Snowy Resort',
      country_name: 'United States of America',
      country_code: 'US',
      region_name: 'Colorado',
      region_code: 'CO',
      lat: 39.5,
      lon: -106.0
    )
  end

  let(:resort_without_snow) do
    FollowTheSnow::Resort.new(
      id: 2,
      name: 'Dry Resort',
      country_name: 'United States of America',
      country_code: 'US',
      region_name: 'California',
      region_code: 'CA',
      lat: 37.5,
      lon: -119.0
    )
  end

  let(:resort_in_canada) do
    FollowTheSnow::Resort.new(
      id: 3,
      name: 'Whistler',
      country_name: 'Canada',
      country_code: 'CA',
      region_name: 'British Columbia',
      region_code: 'BC',
      lat: 50.1,
      lon: -122.9
    )
  end

  let(:resorts) { [resort_with_snow, resort_without_snow, resort_in_canada] }
  let(:context) { described_class.new(resorts: resorts) }

  before do
    # Stub forecasts for resort with snow
    allow(resort_with_snow).to receive(:forecasts).and_return([
                                                                FollowTheSnow::Forecast.new(
                                                                  name: 'Monday',
                                                                  time_of_day: 'Mon',
                                                                  snow: 5.5,
                                                                  temp: '32°F',
                                                                  short: 'Snow',
                                                                  wind_speed: '10 mph',
                                                                  wind_gust: '15 mph',
                                                                  wind_direction: 'N'
                                                                ),
                                                                FollowTheSnow::Forecast.new(
                                                                  name: 'Tuesday',
                                                                  time_of_day: 'Tue',
                                                                  snow: 2.3,
                                                                  temp: '28°F',
                                                                  short: 'Snow',
                                                                  wind_speed: '12 mph',
                                                                  wind_gust: '18 mph',
                                                                  wind_direction: 'NW'
                                                                )
                                                              ])

    # Stub forecasts for resort without snow
    allow(resort_without_snow).to receive(:forecasts).and_return([
                                                                   FollowTheSnow::Forecast.new(
                                                                     name: 'Monday',
                                                                     time_of_day: 'Mon',
                                                                     snow: 0,
                                                                     temp: '45°F',
                                                                     short: 'Clear',
                                                                     wind_speed: '5 mph',
                                                                     wind_gust: '8 mph',
                                                                     wind_direction: 'S'
                                                                   )
                                                                 ])

    # Stub forecasts for Canadian resort
    allow(resort_in_canada).to receive(:forecasts).and_return([
                                                                FollowTheSnow::Forecast.new(
                                                                  name: 'Monday',
                                                                  time_of_day: 'Mon',
                                                                  snow: 3.2,
                                                                  temp: '30°F',
                                                                  short: 'Snow',
                                                                  wind_speed: '8 mph',
                                                                  wind_gust: '12 mph',
                                                                  wind_direction: 'W'
                                                                )
                                                              ])
  end

  describe '#nearby_resorts' do
    let(:neighbor) do
      FollowTheSnow::Resort.new(id: 4, name: 'Neighbor', country_name: 'United States of America', region_name: 'Colorado', lat: 39.6, lon: -106.1)
    end
    let(:resorts) { [resort_with_snow, resort_without_snow, resort_in_canada, neighbor] }

    it 'returns resorts within 150 km, nearest first, excluding itself' do
      expect(context.nearby_resorts(resort_with_snow)).to eq([{ resort: neighbor, km: 14 }])
    end
  end

  describe '#more_snow_nearby' do
    def summary(next7d)
      { next_7d: next7d }
    end

    it 'points to the snowiest neighbor only when it has double and 3 inches more' do
      allow(context).to receive(:snow_summary).and_return(summary(4.0))

      expect(context.more_snow_nearby(resort_with_snow, [{ next_7d: 8.0 }])).to eq({ next_7d: 8.0 })
      expect(context.more_snow_nearby(resort_with_snow, [{ next_7d: 6.9 }])).to be_nil
    end

    it 'needs 3 inches more even when the resort has almost none' do
      allow(context).to receive(:snow_summary).and_return(summary(0.5))

      expect(context.more_snow_nearby(resort_with_snow, [{ next_7d: 2.0 }])).to be_nil
      expect(context.more_snow_nearby(resort_with_snow, [])).to be_nil
    end
  end

  describe '#snowiest_area' do
    it 'picks the other area with the deepest 16-day forecast, ignoring dry ones' do
      allow(context).to receive(:snow_summary) do |resort|
        { next_16d: { 1 => 4.0, 2 => 0.0 }.fetch(resort.id) }
      end

      regions = context.regions_of('United States of America')

      expect(context.snowiest_area(regions, except: 'Utah')).to eq('Colorado')
      expect(context.snowiest_area(regions, except: 'Colorado')).to be_nil
    end
  end

  describe '#scope_description' do
    it 'leads with the count and the snowiest resort' do
      allow(context).to receive(:snow_summary) { |r| { next_7d: { 1 => 4.0, 2 => 0.0, 3 => 0.0 }.fetch(r.id) } }

      expect(context.scope_description([resort_with_snow, resort_without_snow], 'in Colorado'))
        .to eq('1 of 2 ski resorts in Colorado has snow in the next 7 days. Most: Snowy Resort, 4.0 inches (10.16 cm). 16-day snow forecasts, updated daily.')
    end
  end

  describe '#area_rows' do
    it 'ranks snowy areas by their best resort and lists dry ones alphabetically' do
      allow(context).to receive(:snow_summary) do |resort|
        { next_7d: { 1 => 4.0, 2 => 0.0, 3 => 6.0 }.fetch(resort.id), next_16d: 0 }
      end

      snowing, dry = context.area_rows(context.resorts.group_by(&:region_name))

      expect(snowing.map { |row| [row[:name], row[:snowing], row[:total]] }).to eq([['British Columbia', 1, 1], ['Colorado', 1, 1]])
      expect(dry.map { |row| row[:name] }).to eq(['California'])
    end
  end

  describe '#terrain_runs' do
    it 'orders runs from easiest to hardest with unknown kinds last' do
      resort = FollowTheSnow::Resort.new(runs: { 'other' => {}, 'expert' => {}, 'easy' => {}, 'novice' => {} })

      expect(context.terrain_runs(resort).map(&:first)).to eq(%w[Novice Easy Expert Other])
    end
  end

  describe '#safe_url' do
    it 'only allows http(s) links from OpenStreetMap data' do
      expect(context.safe_url('https://www.steamboat.com/')).to eq('https://www.steamboat.com/')
      expect(context.safe_url('javascript:alert(1)')).to be_nil
      expect(context.safe_url(nil)).to be_nil
    end
  end

  describe '#day_callout' do
    it 'calls out the biggest day once it reaches snow-day size' do
      expect(context.day_callout(resort_with_snow)).to include(label: 'Snow day', inches: 5.5, date: 'Mon')
    end

    it 'says nothing when no day reaches 2 inches' do
      expect(context.day_callout(resort_without_snow)).to be_nil
    end
  end

  describe '#precip_status' do
    it 'classifies by freezing level against base and summit (ft)' do
      expect(context.precip_status(0, 9000, 7000, 10_000)).to eq(:dry)
      expect(context.precip_status(0.2, 6500, 7000, 10_000)).to eq(:snow)
      expect(context.precip_status(0.2, 8500, 7000, 10_000)).to eq(:mixed)
      expect(context.precip_status(0.2, 11_000, 7000, 10_000)).to eq(:rain)
      expect(context.precip_status(0.2, 8500, nil, nil)).to eq(:unknown)
    end
  end

  describe '#snow_or_rain' do
    let(:day) { Date.new(2023, 3, 14) }
    let(:mountain) do
      FollowTheSnow::Resort.new(id: 9, name: 'Mountain', lat: 39.5, lon: -106.0, min_elevation: 2000, max_elevation: 3000)
    end

    before do
      forecast = ->(temp) { FollowTheSnow::Forecast.new(time_of_day: day, snow: 0..1.0, precipitation: 0.3, temp: temp) }
      hour     = lambda { |h, precip, level|
        FollowTheSnow::HourlyForecast.new(time: Time.new(2023, 3, 14, h, 0, 0, -21_600), precipitation: precip, freezing_level: level)
      }
      allow(mountain).to receive_messages(
        forecasts: [forecast.call(20.0..30.0)],
        base_forecasts: [forecast.call(28.0..38.0)],
        hourly_forecasts: [hour.call(3, 0.1, 6000), hour.call(15, 0.0, 9000)]
      )
    end

    it 'uses the freezing level of the hours with precipitation' do
      row = context.snow_or_rain(mountain).first

      expect(row).to include(snow_level: 6000, status: :snow, summit_temp: 20.0..30.0, base_temp: 28.0..38.0)
    end
  end

  describe '#snow_summary' do
    it 'sums forward totals from hourly data so past snow is not counted twice' do
      allow(resort_with_snow).to receive_messages(
        past_snowfall: 1.25,
        hourly_forecasts: [FollowTheSnow::HourlyForecast.new(snowfall: 0.5), FollowTheSnow::HourlyForecast.new(snowfall: nil)]
      )

      expect(context.snow_summary(resort_with_snow)).to eq(past_72h: 1.25, next_24h: 0.5, next_7d: 0.5, next_16d: 0.5)
    end
  end

  describe '#format_snow_total' do
    {
      0 => '0″', 5 => '5″', 12.5 => '13″', 7.849 => '7.8″', 0.5 => '0.5″', 0.138 => '0.1″'
    }.each do |inches, text|
      it "renders #{inches} in as a snow value reading #{text}" do
        result = context.format_snow_total(inches)
        expect(result).to eq(%(<data value="#{inches.to_f.round(2)}" data-k="s">#{text}</data>))
        expect(result.html_safe?).to be(true)
      end
    end
  end

  describe '#inches_to_metric' do
    it 'converts inches to centimeters for values >= 1cm' do
      expect(context.inches_to_metric(5)).to eq('12.7 cm')
    end

    it 'converts inches to millimeters for values < 1cm' do
      expect(context.inches_to_metric(0.138)).to eq('3.51 mm')
    end

    it 'handles the boundary case near 1cm' do
      expect(context.inches_to_metric(0.5)).to eq('1.27 cm')
    end
  end

  describe '#snow?' do
    it 'returns true if number exists in string' do
      expect(context.snow?('There is 3 inches of snow')).to be(true)
      expect(context.snow?('Snowfall: 0.5')).to be(true)
      expect(context.snow?('Snowfall: -0.5')).to be(false)
    end

    it 'returns true for positive snow values' do
      expect(context.snow?(5.5)).to be(true)
    end

    it 'returns false for zero' do
      expect(context.snow?(0)).to be(false)
    end

    it 'returns false for negative values' do
      expect(context.snow?(-1)).to be(false)
    end

    it 'handles string values' do
      expect(context.snow?('2.5')).to be(true)
      expect(context.snow?('0')).to be(false)
    end
  end

  describe '#snow_indicator' do
    it 'returns an HTML-safe snowflake indicator' do
      indicator = context.snow_indicator
      expect(indicator).to include('❄️')
      expect(indicator).to include('snow-indicator')
      expect(indicator).to include('aria-label="Snow in forecast"')
    end

    it 'returns html_safe string' do
      indicator = context.snow_indicator
      expect(indicator.html_safe?).to be(true)
    end
  end

  describe '#small_country?' do
    it 'returns true for countries with resorts at or below threshold' do
      # Create a country with exactly SMALL_COUNTRY_THRESHOLD resorts
      small_resorts = (1..FollowTheSnow::Builder::Context::SMALL_COUNTRY_THRESHOLD).map do |i|
        FollowTheSnow::Resort.new(
          id: i + 100,
          name: "Small Resort #{i}",
          country_name: 'Small Country',
          country_code: 'SC',
          region_name: 'Region A',
          region_code: 'RA',
          lat: 40.0,
          lon: -100.0
        )
      end

      context_with_small = described_class.new(resorts: resorts + small_resorts)
      expect(context_with_small.small_country?('Small Country')).to be(true)
    end

    it 'returns false for countries with more resorts than threshold' do
      # USA has 2 resorts, which is below threshold, but let's add more
      large_resorts = (1..(FollowTheSnow::Builder::Context::SMALL_COUNTRY_THRESHOLD + 1)).map do |i|
        FollowTheSnow::Resort.new(
          id: i + 200,
          name: "Large Resort #{i}",
          country_name: 'Large Country',
          country_code: 'LC',
          region_name: 'Region B',
          region_code: 'RB',
          lat: 40.0,
          lon: -100.0
        )
      end

      context_with_large = described_class.new(resorts: resorts + large_resorts)
      expect(context_with_large.small_country?('Large Country')).to be(false)
    end

    it 'returns true for Canada with 1 resort (below threshold)' do
      # Canada only has 1 resort in our test data
      expect(context.small_country?('Canada')).to be(true)
    end

    it 'returns true for USA with 2 resorts (below threshold)' do
      # USA has 2 resorts in our test data
      expect(context.small_country?('United States of America')).to be(true)
    end
  end
end
