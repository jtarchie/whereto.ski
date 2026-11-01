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

  describe '#snowiest_sibling_region' do
    it 'picks the sibling region with the deepest 16-day forecast, ignoring dry ones' do
      allow(context).to receive(:snow_summary) do |resort|
        { next_16d: { 1 => 4.0, 2 => 0.0 }.fetch(resort.id) }
      end

      expect(context.snowiest_sibling_region('Utah', 'United States of America')).to eq('Colorado')
      expect(context.snowiest_sibling_region('Colorado', 'United States of America')).to be_nil
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

  describe '#country_has_snow?' do
    it 'returns true when a country has resorts with snow' do
      expect(context.country_has_snow?('United States of America')).to be(true)
    end

    it 'returns true for Canada with snow' do
      expect(context.country_has_snow?('Canada')).to be(true)
    end

    it 'returns false when no resorts in country have snow' do
      # Add a new country with no snow
      resort_no_snow_country = FollowTheSnow::Resort.new(
        id: 4,
        name: 'Warm Resort',
        country_name: 'Spain',
        country_code: 'ES',
        region_name: 'Andalusia',
        region_code: 'AN',
        lat: 37.0,
        lon: -3.0
      )
      allow(resort_no_snow_country).to receive(:forecasts).and_return([
                                                                        FollowTheSnow::Forecast.new(
                                                                          name: 'Monday',
                                                                          time_of_day: 'Mon',
                                                                          snow: 0,
                                                                          temp: '60°F',
                                                                          short: 'Clear',
                                                                          wind_speed: '5 mph',
                                                                          wind_gust: '8 mph',
                                                                          wind_direction: 'S'
                                                                        )
                                                                      ])

      context_with_spain = described_class.new(resorts: resorts + [resort_no_snow_country])
      expect(context_with_spain.country_has_snow?('Spain')).to be(false)
    end
  end

  describe '#state_has_snow?' do
    it 'returns true when a state has resorts with snow' do
      expect(context.state_has_snow?('Colorado')).to be(true)
    end

    it 'returns false when a state has no resorts with snow' do
      expect(context.state_has_snow?('California')).to be(false)
    end

    it 'returns true for British Columbia' do
      expect(context.state_has_snow?('British Columbia')).to be(true)
    end
  end

  describe '#country_snow_count' do
    it 'counts resorts with snow in a country' do
      expect(context.country_snow_count('United States of America')).to eq(1)
    end

    it 'returns 0 when no resorts have snow' do
      resort_ca_no_snow = FollowTheSnow::Resort.new(
        id: 5,
        name: 'Another CA Resort',
        country_name: 'United States of America',
        country_code: 'US',
        region_name: 'California',
        region_code: 'CA',
        lat: 38.0,
        lon: -120.0
      )
      allow(resort_ca_no_snow).to receive(:forecasts).and_return([
                                                                   FollowTheSnow::Forecast.new(name: 'Mon', time_of_day: 'Mon', snow: 0,
                                                                                               temp: '50°F', short: 'Clear',
                                                                                               wind_speed: '5 mph', wind_gust: '8 mph', wind_direction: 'S')
                                                                 ])

      context_extended = described_class.new(resorts: resorts + [resort_ca_no_snow])
      # Still only 1 resort with snow in USA (Colorado resort)
      expect(context_extended.country_snow_count('United States of America')).to eq(1)
    end
  end

  describe '#state_snow_count' do
    it 'counts resorts with snow in a state' do
      expect(context.state_snow_count('Colorado')).to eq(1)
    end

    it 'returns 0 when no resorts have snow in state' do
      expect(context.state_snow_count('California')).to eq(0)
    end
  end

  describe '#total_snow_for_country' do
    it 'sums all snow for resorts in a country' do
      # USA has one resort with 5.5 + 2.3 = 7.8 inches
      expect(context.total_snow_for_country('United States of America')).to eq(7.8)
    end

    it 'returns correct total for Canada' do
      # Canada has one resort with 3.2 inches
      expect(context.total_snow_for_country('Canada')).to eq(3.2)
    end
  end

  describe '#total_snow_for_state' do
    it 'sums all snow for resorts in a state' do
      expect(context.total_snow_for_state('Colorado')).to eq(7.8)
    end

    it 'returns 0 for state with no snow' do
      expect(context.total_snow_for_state('California')).to eq(0)
    end
  end

  describe '#top_snowy_resorts' do
    it 'returns top resorts sorted by total snow' do
      results = context.top_snowy_resorts(limit: 10)

      expect(results.length).to eq(2) # Only 2 resorts have snow
      expect(results[0][:resort].name).to eq('Snowy Resort')
      expect(results[0][:total]).to eq(7.8)
      expect(results[1][:resort].name).to eq('Whistler')
      expect(results[1][:total]).to eq(3.2)
    end

    it 'respects the limit parameter' do
      results = context.top_snowy_resorts(limit: 1)
      expect(results.length).to eq(1)
      expect(results[0][:resort].name).to eq('Snowy Resort')
    end

    it 'excludes resorts with no snow' do
      results      = context.top_snowy_resorts(limit: 10)
      resort_names = results.map { |r| r[:resort].name }
      expect(resort_names).not_to include('Dry Resort')
    end
  end

  describe '#resorts_with_snow_today' do
    it 'returns resorts with snow in first forecast' do
      results = context.resorts_with_snow_today(limit: 10)

      expect(results.length).to eq(2)
      expect(results.map { |r| r[:resort].name }).to include('Snowy Resort', 'Whistler')
    end

    it 'sorts by snow amount descending' do
      results = context.resorts_with_snow_today(limit: 10)

      expect(results[0][:resort].name).to eq('Snowy Resort') # 5.5 inches
      expect(results[0][:snow]).to eq(5.5)
      expect(results[1][:resort].name).to eq('Whistler') # 3.2 inches
      expect(results[1][:snow]).to eq(3.2)
    end

    it 'excludes resorts without snow today' do
      results      = context.resorts_with_snow_today(limit: 10)
      resort_names = results.map { |r| r[:resort].name }
      expect(resort_names).not_to include('Dry Resort')
    end

    it 'respects the limit parameter' do
      results = context.resorts_with_snow_today(limit: 1)
      expect(results.length).to eq(1)
      expect(results[0][:resort].name).to eq('Snowy Resort')
    end
  end

  describe '#regional_summaries' do
    it 'returns summaries for all countries with snow' do
      summaries = context.regional_summaries

      expect(summaries.length).to eq(2) # USA and Canada
    end

    it 'includes correct data for each country' do
      summaries   = context.regional_summaries
      usa_summary = summaries.find { |s| s[:country] == 'United States of America' }

      expect(usa_summary[:total_snow]).to eq(7.8)
      expect(usa_summary[:resort_count]).to eq(1) # Only Colorado resort has snow
      expect(usa_summary[:total_resorts]).to eq(2) # Colorado + California
    end

    it 'sorts by total snow descending' do
      summaries = context.regional_summaries

      expect(summaries[0][:country]).to eq('United States of America') # 7.8 inches
      expect(summaries[1][:country]).to eq('Canada') # 3.2 inches
    end

    it 'excludes countries with no snow' do
      resort_no_snow = FollowTheSnow::Resort.new(
        id: 6,
        name: 'Beach Resort',
        country_name: 'Mexico',
        country_code: 'MX',
        region_name: 'Baja',
        region_code: 'BJ',
        lat: 32.0,
        lon: -117.0
      )
      allow(resort_no_snow).to receive(:forecasts).and_return([
                                                                FollowTheSnow::Forecast.new(name: 'Mon', time_of_day: 'Mon', snow: 0,
                                                                                            temp: '75°F', short: 'Sunny',
                                                                                            wind_speed: '5 mph', wind_gust: '8 mph', wind_direction: 'W')
                                                              ])

      context_with_mexico = described_class.new(resorts: resorts + [resort_no_snow])
      summaries           = context_with_mexico.regional_summaries

      expect(summaries.map { |s| s[:country] }).not_to include('Mexico')
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

  describe '#any_snow?' do
    it 'returns true when resort has snow in forecast' do
      expect(context.any_snow?(resort_with_snow)).to be(true)
    end

    it 'returns false when resort has no snow in forecast' do
      expect(context.any_snow?(resort_without_snow)).to be(false)
    end
  end

  describe '#total_snow_for' do
    it 'returns total snow amount for a resort' do
      # resort_with_snow has 5.5 + 2.3 = 7.8 inches total
      expect(context.total_snow_for(resort_with_snow)).to eq(7.8)
    end

    it 'returns 0 for resort without snow' do
      expect(context.total_snow_for(resort_without_snow)).to eq(0)
    end
  end
end
