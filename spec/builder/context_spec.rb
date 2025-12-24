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
    it 'formats zero with both units' do
      result = context.format_snow_total(0)
      expect(result).to include('<span class="imperial">0"</span>')
      expect(result).to include('<span class="metric">0 cm</span>')
      expect(result.html_safe?).to be(true)
    end

    it 'formats whole numbers with both units' do
      result = context.format_snow_total(5)
      expect(result).to include('<span class="imperial">5"</span>')
      expect(result).to include('<span class="metric">12.7 cm</span>')
      expect(result.html_safe?).to be(true)
    end

    it 'formats decimals correctly with both units' do
      result = context.format_snow_total(12.5)
      expect(result).to include('<span class="imperial">12.5"</span>')
      expect(result).to include('<span class="metric">31.75 cm</span>')
      expect(result.html_safe?).to be(true)
    end

    it 'rounds to one decimal place' do
      result = context.format_snow_total(7.849)
      expect(result).to include('<span class="imperial">7.8"</span>')
      expect(result).to include('<span class="metric">19.94 cm</span>')
      expect(result.html_safe?).to be(true)
    end

    it 'formats small amounts correctly with millimeters' do
      result = context.format_snow_total(0.5)
      expect(result).to include('<span class="imperial">0.5"</span>')
      expect(result).to include('<span class="metric">1.27 cm</span>')
      expect(result.html_safe?).to be(true)
    end

    it 'formats very small amounts with millimeters' do
      result = context.format_snow_total(0.138)
      expect(result).to include('<span class="imperial">0.1"</span>')
      expect(result).to include('<span class="metric">3.51 mm</span>')
      expect(result.html_safe?).to be(true)
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

  describe '#best_ski_days' do
    let(:resort_with_varied_conditions) do
      FollowTheSnow::Resort.new(
        id: 10,
        name: 'Varied Resort',
        country_name: 'United States of America',
        country_code: 'US',
        region_name: 'Colorado',
        region_code: 'CO',
        lat: 39.5,
        lon: -106.0
      )
    end
    let(:varied_context) { described_class.new(resorts: [resort_with_varied_conditions]) }

    before do
      allow(resort_with_varied_conditions).to receive(:forecasts).and_return([
                                                                               FollowTheSnow::Forecast.new(
                                                                                 name: 'Monday',
                                                                                 time_of_day: Date.new(2023, 3, 14),
                                                                                 snow: 8.0,
                                                                                 temp: 25..32,
                                                                                 wind_speed: 5..10,
                                                                                 wind_gust: '15 mph',
                                                                                 wind_direction: 'N'
                                                                               ),
                                                                               FollowTheSnow::Forecast.new(
                                                                                 name: 'Tuesday',
                                                                                 time_of_day: Date.new(2023, 3, 15),
                                                                                 snow: 0.0,
                                                                                 temp: 35..45,
                                                                                 wind_speed: 30..45,
                                                                                 wind_gust: '55 mph',
                                                                                 wind_direction: 'W'
                                                                               ),
                                                                               FollowTheSnow::Forecast.new(
                                                                                 name: 'Wednesday',
                                                                                 time_of_day: Date.new(2023, 3, 16),
                                                                                 snow: 2.0,
                                                                                 temp: 28..35,
                                                                                 wind_speed: 8..12,
                                                                                 wind_gust: '18 mph',
                                                                                 wind_direction: 'NW'
                                                                               )
                                                                             ])
    end

    it 'returns array of scored days' do
      days = varied_context.best_ski_days(resort_with_varied_conditions, limit: 3)

      expect(days).to be_an(Array)
      expect(days.length).to eq(3)
    end

    it 'includes required keys in each day' do
      days = varied_context.best_ski_days(resort_with_varied_conditions, limit: 3)

      expect(days).to all(include(:date, :name, :score, :rating, :reasons, :snow))
    end

    it 'scores powder days higher' do
      days = varied_context.best_ski_days(resort_with_varied_conditions, limit: 3)

      powder_day  = days.find { |d| d[:name] == 'Monday' }
      no_snow_day = days.find { |d| d[:name] == 'Tuesday' }

      expect(powder_day[:score]).to be > no_snow_day[:score]
    end

    it 'penalizes high wind days' do
      days = varied_context.best_ski_days(resort_with_varied_conditions, limit: 3)

      windy_day = days.find { |d| d[:name] == 'Tuesday' }
      calm_day  = days.find { |d| d[:name] == 'Wednesday' }

      # Tuesday has 30-45mph winds, Wednesday has 8-12mph
      expect(calm_day[:score]).to be > windy_day[:score]
    end

    it 'assigns correct ratings based on score' do
      days          = varied_context.best_ski_days(resort_with_varied_conditions, limit: 3)
      valid_ratings = %w[Epic Great Good Fair Poor]

      expect(days.map { |d| d[:rating] }).to all(be_in(valid_ratings))
    end

    it 'respects limit parameter' do
      days = varied_context.best_ski_days(resort_with_varied_conditions, limit: 2)
      expect(days.length).to eq(2)
    end

    it 'includes snow amount in each day' do
      days = varied_context.best_ski_days(resort_with_varied_conditions, limit: 3)

      powder_day = days.find { |d| d[:name] == 'Monday' }
      expect(powder_day[:snow]).to eq(8.0)
    end
  end

  describe '#best_day_to_ski' do
    let(:resort_with_varied_conditions) do
      FollowTheSnow::Resort.new(
        id: 10,
        name: 'Varied Resort',
        country_name: 'United States of America',
        country_code: 'US',
        region_name: 'Colorado',
        region_code: 'CO',
        lat: 39.5,
        lon: -106.0
      )
    end
    let(:varied_context) { described_class.new(resorts: [resort_with_varied_conditions]) }

    before do
      allow(resort_with_varied_conditions).to receive(:forecasts).and_return([
                                                                               FollowTheSnow::Forecast.new(
                                                                                 name: 'Monday',
                                                                                 time_of_day: Date.new(2023, 3, 14),
                                                                                 snow: 0.5,
                                                                                 temp: 30..40,
                                                                                 wind_speed: 10..15,
                                                                                 wind_gust: '20 mph',
                                                                                 wind_direction: 'N'
                                                                               ),
                                                                               FollowTheSnow::Forecast.new(
                                                                                 name: 'Tuesday',
                                                                                 time_of_day: Date.new(2023, 3, 15),
                                                                                 snow: 6.0,
                                                                                 temp: 25..30,
                                                                                 wind_speed: 5..8,
                                                                                 wind_gust: '12 mph',
                                                                                 wind_direction: 'NW'
                                                                               ),
                                                                               FollowTheSnow::Forecast.new(
                                                                                 name: 'Wednesday',
                                                                                 time_of_day: Date.new(2023, 3, 16),
                                                                                 snow: 0.0,
                                                                                 temp: 35..45,
                                                                                 wind_speed: 8..12,
                                                                                 wind_gust: '18 mph',
                                                                                 wind_direction: 'W'
                                                                               )
                                                                             ])
    end

    it 'returns the day with highest score' do
      best = varied_context.best_day_to_ski(resort_with_varied_conditions)

      # Tuesday has 6" snow + calm winds = should be best
      expect(best[:name]).to eq('Tuesday')
    end

    it 'returns a hash with expected keys' do
      best = varied_context.best_day_to_ski(resort_with_varied_conditions)

      expect(best).to have_key(:score)
      expect(best).to have_key(:rating)
      expect(best).to have_key(:reasons)
    end
  end

  describe '#best_ski_days_for_region' do
    let(:resort_vail) do
      FollowTheSnow::Resort.new(
        id: 20,
        name: 'Vail',
        country_name: 'United States of America',
        country_code: 'US',
        region_name: 'Colorado',
        region_code: 'CO',
        lat: 39.6,
        lon: -106.4
      )
    end

    let(:resort_breckenridge) do
      FollowTheSnow::Resort.new(
        id: 21,
        name: 'Breckenridge',
        country_name: 'United States of America',
        country_code: 'US',
        region_name: 'Colorado',
        region_code: 'CO',
        lat: 39.5,
        lon: -106.1
      )
    end

    let(:region_context) { described_class.new(resorts: [resort_vail, resort_breckenridge]) }

    before do
      allow(resort_vail).to receive(:forecasts).and_return([
                                                             FollowTheSnow::Forecast.new(
                                                               name: 'Monday',
                                                               time_of_day: Date.new(2023, 3, 14),
                                                               snow: 5.0,
                                                               temp: 25..32,
                                                               wind_speed: 8..12,
                                                               wind_gust: '18 mph',
                                                               wind_direction: 'N'
                                                             ),
                                                             FollowTheSnow::Forecast.new(
                                                               name: 'Tuesday',
                                                               time_of_day: Date.new(2023, 3, 15),
                                                               snow: 0.0,
                                                               temp: 35..42,
                                                               wind_speed: 5..10,
                                                               wind_gust: '15 mph',
                                                               wind_direction: 'W'
                                                             )
                                                           ])

      allow(resort_breckenridge).to receive(:forecasts).and_return([
                                                                     FollowTheSnow::Forecast.new(
                                                                       name: 'Monday',
                                                                       time_of_day: Date.new(2023, 3, 14),
                                                                       snow: 3.0,
                                                                       temp: 28..35,
                                                                       wind_speed: 10..15,
                                                                       wind_gust: '20 mph',
                                                                       wind_direction: 'NW'
                                                                     ),
                                                                     FollowTheSnow::Forecast.new(
                                                                       name: 'Tuesday',
                                                                       time_of_day: Date.new(2023, 3, 15),
                                                                       snow: 0.0,
                                                                       temp: 32..40,
                                                                       wind_speed: 6..12,
                                                                       wind_gust: '16 mph',
                                                                       wind_direction: 'W'
                                                                     )
                                                                   ])
    end

    it 'returns array of aggregated day data' do
      days = region_context.best_ski_days_for_region([resort_vail, resort_breckenridge], limit: 2)

      expect(days).to be_an(Array)
      expect(days.length).to eq(2)
    end

    it 'includes aggregated stats in each day' do
      days = region_context.best_ski_days_for_region([resort_vail, resort_breckenridge], limit: 2)

      expect(days).to all(include(:name, :avg_score, :rating, :total_resorts,
                                  :resorts_with_snow, :epic_count, :great_count, :good_count, :max_snow))
    end

    it 'correctly counts resorts with snow' do
      days = region_context.best_ski_days_for_region([resort_vail, resort_breckenridge], limit: 2)

      monday  = days.find { |d| d[:name] == 'Monday' }
      tuesday = days.find { |d| d[:name] == 'Tuesday' }

      # Both resorts have snow on Monday
      expect(monday[:resorts_with_snow]).to eq(2)

      # Neither resort has snow on Tuesday
      expect(tuesday[:resorts_with_snow]).to eq(0)
    end

    it 'calculates average score across resorts' do
      days = region_context.best_ski_days_for_region([resort_vail, resort_breckenridge], limit: 2)

      monday = days.find { |d| d[:name] == 'Monday' }

      # Should be an average of both resort scores
      expect(monday[:avg_score]).to be_between(50, 100)
    end

    it 'tracks max snow amount' do
      days = region_context.best_ski_days_for_region([resort_vail, resort_breckenridge], limit: 2)

      monday = days.find { |d| d[:name] == 'Monday' }

      # Max snow is 5.0" from Vail
      expect(monday[:max_snow]).to eq(5.0)
    end

    it 'counts total resorts correctly' do
      days = region_context.best_ski_days_for_region([resort_vail, resort_breckenridge], limit: 2)

      expect(days.map { |d| d[:total_resorts] }).to all(eq(2))
    end

    it 'respects limit parameter' do
      days = region_context.best_ski_days_for_region([resort_vail, resort_breckenridge], limit: 1)
      expect(days.length).to eq(1)
    end
  end
end
