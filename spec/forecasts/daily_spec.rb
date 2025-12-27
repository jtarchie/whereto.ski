# frozen_string_literal: true

require 'spec_helper'

RSpec.describe(FollowTheSnow::Forecast::Daily) do
  describe 'ForecastDelegate' do
    let(:valid_forecast) do
      FollowTheSnow::Forecast.new(
        name: 'Tue 03/14',
        short: 'Snow fall: Moderate intensity',
        snow: 0..2.5,
        temp: 25.0..38.5,
        apparent_temp: 20.0..35.0,
        time_of_day: Date.new(2023, 3, 14),
        wind_direction: :NW,
        wind_gust: 0..25.5,
        wind_speed: 0..15.0,
        uv_index: 4.2,
        sunshine_duration: 21_600,
        precipitation_probability: 75,
        precipitation: 0.5,
        rain: 0.0
      )
    end

    let(:nil_temp_forecast) do
      FollowTheSnow::Forecast.new(
        name: 'Wed 03/15',
        short: nil,
        snow: 0..0,
        temp: nil..nil,
        apparent_temp: nil..nil,
        time_of_day: Date.new(2023, 3, 15),
        wind_direction: nil,
        wind_gust: nil..nil,
        wind_speed: nil..nil,
        uv_index: nil,
        sunshine_duration: nil,
        precipitation_probability: nil,
        precipitation: nil,
        rain: nil
      )
    end

    let(:partial_nil_forecast) do
      FollowTheSnow::Forecast.new(
        name: 'Thu 03/16',
        short: 'Overcast',
        snow: 0..nil,
        temp: nil..45.0,
        apparent_temp: nil..40.0,
        time_of_day: Date.new(2023, 3, 16),
        wind_direction: :S,
        wind_gust: 0..nil,
        wind_speed: 0..nil,
        uv_index: nil,
        sunshine_duration: 14_400,
        precipitation_probability: 30,
        precipitation: 0.1,
        rain: 0.1
      )
    end

    describe '#valid?' do
      it 'returns true for forecast with valid essential data' do
        daily    = described_class.new(forecasts: [valid_forecast])
        delegate = daily.forecasts.first
        # If we got the delegate back from forecasts, it was valid
        expect(delegate).not_to be_nil
      end

      it 'filters out forecasts with nil temperature range' do
        daily     = described_class.new(forecasts: [nil_temp_forecast])
        forecasts = daily.forecasts
        expect(forecasts).to be_empty
      end

      it 'keeps forecasts with partial nil temperature (one value present)' do
        daily     = described_class.new(forecasts: [partial_nil_forecast])
        forecasts = daily.forecasts
        expect(forecasts.length).to eq(1)
      end
    end

    describe '#temp' do
      it 'returns formatted temperature for valid data' do
        daily    = described_class.new(forecasts: [valid_forecast])
        delegate = daily.forecasts.first
        expect(delegate.temp).to include('38.5 °F')
        expect(delegate.temp).to include('°C')
      end

      it 'returns placeholder for nil temperature' do
        daily    = described_class.new(forecasts: [partial_nil_forecast])
        delegate = daily.forecasts.first
        # partial_nil_forecast has temp: nil..45.0, so .end is 45.0
        expect(delegate.temp).to include('45')
      end
    end

    describe '#apparent_temp' do
      it 'returns formatted apparent temp for valid data' do
        daily    = described_class.new(forecasts: [valid_forecast])
        delegate = daily.forecasts.first
        expect(delegate.apparent_temp).to include('35')
        expect(delegate.apparent_temp).to include('°C')
      end
    end

    describe '#snow' do
      it 'returns formatted snow range for valid data' do
        daily    = described_class.new(forecasts: [valid_forecast])
        delegate = daily.forecasts.first
        expect(delegate.snow).to include('2.5"')
      end

      it 'handles nil snow end gracefully' do
        daily    = described_class.new(forecasts: [partial_nil_forecast])
        delegate = daily.forecasts.first
        expect(delegate.snow).to include('0"')
      end
    end

    describe '#wind_speed' do
      it 'returns formatted wind speed for valid data' do
        daily    = described_class.new(forecasts: [valid_forecast])
        delegate = daily.forecasts.first
        expect(delegate.wind_speed).to include('NW')
        expect(delegate.wind_speed).to include('15')
        expect(delegate.wind_speed).to include('mph')
      end

      it 'handles nil wind speed gracefully' do
        daily    = described_class.new(forecasts: [partial_nil_forecast])
        delegate = daily.forecasts.first
        expect(delegate.wind_speed).to include('-- mph')
      end
    end

    describe '#wind_gust' do
      it 'returns formatted wind gust for valid data' do
        daily    = described_class.new(forecasts: [valid_forecast])
        delegate = daily.forecasts.first
        expect(delegate.wind_gust).to include('25.5')
        expect(delegate.wind_gust).to include('mph')
      end

      it 'handles nil wind gust gracefully' do
        daily    = described_class.new(forecasts: [partial_nil_forecast])
        delegate = daily.forecasts.first
        expect(delegate.wind_gust).to include('-- mph')
      end
    end

    describe '#uv_index' do
      it 'returns UV index for valid data' do
        daily    = described_class.new(forecasts: [valid_forecast])
        delegate = daily.forecasts.first
        expect(delegate.uv_index).to eq(4.2)
      end

      it 'returns placeholder for nil UV index' do
        daily    = described_class.new(forecasts: [partial_nil_forecast])
        delegate = daily.forecasts.first
        expect(delegate.uv_index).to eq('--')
      end
    end

    describe '#precipitation_probability' do
      it 'returns formatted probability for valid data' do
        daily    = described_class.new(forecasts: [valid_forecast])
        delegate = daily.forecasts.first
        expect(delegate.precipitation_probability).to eq('75%')
      end
    end

    describe '#sunshine_duration' do
      it 'returns formatted duration for valid data' do
        daily    = described_class.new(forecasts: [valid_forecast])
        delegate = daily.forecasts.first
        expect(delegate.sunshine_duration).to eq('6h 0m')
      end

      it 'handles nil sunshine duration' do
        # Create a forecast with nil sunshine_duration but valid temp
        forecast = FollowTheSnow::Forecast.new(
          name: 'Test',
          short: 'Clear',
          snow: 0..0,
          temp: 30.0..50.0,
          apparent_temp: 28.0..48.0,
          time_of_day: Date.new(2023, 3, 17),
          wind_direction: :N,
          wind_gust: 0..10.0,
          wind_speed: 0..5.0,
          uv_index: nil,
          sunshine_duration: nil,
          precipitation_probability: 0,
          precipitation: 0.0,
          rain: 0.0
        )
        daily    = described_class.new(forecasts: [forecast])
        delegate = daily.forecasts.first
        expect(delegate.sunshine_duration).to eq('0m')
      end
    end

    describe 'filtering behavior' do
      it 'filters out completely invalid forecasts but keeps valid ones' do
        daily     = described_class.new(
          forecasts: [valid_forecast, nil_temp_forecast, partial_nil_forecast]
        )
        forecasts = daily.forecasts

        # Should have 2 forecasts (valid and partial_nil, not nil_temp)
        expect(forecasts.length).to eq(2)
      end
    end
  end
end
