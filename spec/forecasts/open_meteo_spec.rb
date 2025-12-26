# frozen_string_literal: true

require 'spec_helper'

RSpec.describe(FollowTheSnow::Forecast::OpenMeteo) do
  let(:resort) do
    instance_double(
      FollowTheSnow::Resort,
      id: 1,
      lat: 39.6403,
      lon: -106.3742
    )
  end

  describe '#forecasts' do
    context 'when API returns complete data' do
      before { stub_weather_api }

      it 'parses daily forecasts successfully' do
        open_meteo = described_class.new(resort: resort)
        forecasts  = open_meteo.forecasts

        expect(forecasts).to be_an(Array)
        expect(forecasts.length).to eq(16)
        expect(forecasts.first).to be_a(FollowTheSnow::Forecast)
      end

      it 'includes expected forecast attributes' do
        open_meteo = described_class.new(resort: resort)
        forecast   = open_meteo.forecasts.first

        expect(forecast.name).to eq('Tue 03/14')
        expect(forecast.temp).to be_a(Range)
        expect(forecast.apparent_temp).to be_a(Range)
        expect(forecast.snow).to be_a(Range)
        expect(forecast.wind_speed).to be_a(Range)
        expect(forecast.wind_gust).to be_a(Range)
      end
    end

    context 'when API returns nil values in daily data' do
      before do
        stub_request(:get, /api.open-meteo.com/)
          .to_return(
            status: 200,
            body: {
              'current' => {
                'time' => '2023-03-14T12:00',
                'temperature_2m' => 45.2,
                'relative_humidity_2m' => 65,
                'apparent_temperature' => 42.1,
                'is_day' => 1,
                'precipitation' => 0.0,
                'weather_code' => 2,
                'cloud_cover' => 40,
                'wind_speed_10m' => 8.5,
                'wind_direction_10m' => 225,
                'wind_gusts_10m' => 15.2
              },
              'hourly' => {
                'time' => ['2023-03-14T00:00', '2023-03-14T01:00'],
                'temperature_2m' => [nil, 45.0],
                'relative_humidity_2m' => [nil, 65],
                'apparent_temperature' => [nil, 42.1],
                'precipitation_probability' => [nil, 50],
                'precipitation' => [nil, 0.1],
                'snowfall' => [nil, 0.5],
                'weather_code' => [nil, 71],
                'cloud_cover' => [nil, 40],
                'wind_speed_10m' => [nil, 10.0],
                'wind_direction_10m' => [nil, 180],
                'wind_gusts_10m' => [nil, 20.0],
                'freezing_level_height' => [nil, 8000],
                'visibility' => [nil, 10_000],
                'is_day' => [0, 1]
              },
              'daily' => {
                'time' => %w[2023-03-14 2023-03-15 2023-03-16],
                'weather_code' => [3, nil, 75],
                'temperature_2m_max' => [62.2, nil, 50.7],
                'temperature_2m_min' => [36.8, nil, 23.7],
                'apparent_temperature_max' => [58.3, nil, 45.1],
                'apparent_temperature_min' => [32.1, nil, 18.4],
                'snowfall_sum' => [0.0, nil, 2.95],
                'precipitation_sum' => [0.0, nil, 1.2],
                'rain_sum' => [0.0, nil, 0.0],
                'precipitation_hours' => [0.0, nil, 12.0],
                'precipitation_probability_max' => [5, nil, 85],
                'wind_speed_10m_max' => [12.8, nil, 15.1],
                'wind_gusts_10m_max' => [21.7, nil, 26.8],
                'wind_direction_10m_dominant' => [278, nil, 35],
                'uv_index_max' => [4.2, nil, 2.1],
                'sunshine_duration' => [21_600, nil, 7200]
              }
            }.to_json
          )
      end

      it 'handles nil temperature values gracefully' do
        open_meteo = described_class.new(resort: resort)
        forecasts  = open_meteo.forecasts

        expect(forecasts.length).to eq(3)

        # First day has valid data
        expect(forecasts[0].temp).to eq(36.8..62.2)

        # Second day has nil temperatures - should create nil..nil range
        expect(forecasts[1].temp.begin).to be_nil
        expect(forecasts[1].temp.end).to be_nil

        # Third day has valid data
        expect(forecasts[2].temp).to eq(23.7..50.7)
      end

      it 'handles nil apparent temperature values gracefully' do
        open_meteo = described_class.new(resort: resort)
        forecasts  = open_meteo.forecasts

        expect(forecasts[0].apparent_temp).to eq(32.1..58.3)
        expect(forecasts[1].apparent_temp.begin).to be_nil
        expect(forecasts[1].apparent_temp.end).to be_nil
        expect(forecasts[2].apparent_temp).to eq(18.4..45.1)
      end

      it 'handles nil snowfall values gracefully with zero default' do
        open_meteo = described_class.new(resort: resort)
        forecasts  = open_meteo.forecasts

        expect(forecasts[0].snow).to eq(0..0.0)
        expect(forecasts[1].snow).to eq(0..0) # nil defaults to 0
        expect(forecasts[2].snow).to eq(0..2.95)
      end

      it 'handles nil wind speed values gracefully with zero default' do
        open_meteo = described_class.new(resort: resort)
        forecasts  = open_meteo.forecasts

        expect(forecasts[0].wind_speed).to eq(0..12.8)
        expect(forecasts[1].wind_speed).to eq(0..0) # nil defaults to 0
        expect(forecasts[2].wind_speed).to eq(0..15.1)
      end

      it 'handles nil wind gust values gracefully with zero default' do
        open_meteo = described_class.new(resort: resort)
        forecasts  = open_meteo.forecasts

        expect(forecasts[0].wind_gust).to eq(0..21.7)
        expect(forecasts[1].wind_gust).to eq(0..0) # nil defaults to 0
        expect(forecasts[2].wind_gust).to eq(0..26.8)
      end

      it 'handles nil UV index values gracefully' do
        open_meteo = described_class.new(resort: resort)
        forecasts  = open_meteo.forecasts

        expect(forecasts[0].uv_index).to eq(4.2)
        expect(forecasts[1].uv_index).to be_nil
        expect(forecasts[2].uv_index).to eq(2.1)
      end
    end
  end

  describe '#hourly_forecasts' do
    context 'when API returns nil values in hourly data' do
      before do
        stub_request(:get, /api.open-meteo.com/)
          .to_return(
            status: 200,
            body: {
              'current' => {
                'time' => '2023-03-14T12:00',
                'temperature_2m' => 45.2,
                'relative_humidity_2m' => 65,
                'apparent_temperature' => 42.1,
                'is_day' => 1,
                'precipitation' => 0.0,
                'weather_code' => 2,
                'cloud_cover' => 40,
                'wind_speed_10m' => 8.5,
                'wind_direction_10m' => 225,
                'wind_gusts_10m' => 15.2
              },
              'hourly' => {
                'time' => ['2023-03-14T00:00', '2023-03-14T01:00'],
                'temperature_2m' => [nil, 45.0],
                'relative_humidity_2m' => [nil, 65],
                'apparent_temperature' => [nil, 42.1],
                'precipitation_probability' => [nil, 50],
                'precipitation' => [nil, 0.1],
                'snowfall' => [nil, 0.5],
                'weather_code' => [nil, 71],
                'cloud_cover' => [nil, 40],
                'wind_speed_10m' => [nil, 10.0],
                'wind_direction_10m' => [nil, 180],
                'wind_gusts_10m' => [nil, 20.0],
                'freezing_level_height' => [nil, 8000],
                'visibility' => [nil, 10_000],
                'is_day' => [0, 1]
              },
              'daily' => {
                'time' => ['2023-03-14'],
                'weather_code' => [3],
                'temperature_2m_max' => [62.2],
                'temperature_2m_min' => [36.8],
                'apparent_temperature_max' => [58.3],
                'apparent_temperature_min' => [32.1],
                'snowfall_sum' => [0.0],
                'precipitation_sum' => [0.0],
                'rain_sum' => [0.0],
                'precipitation_hours' => [0.0],
                'precipitation_probability_max' => [5],
                'wind_speed_10m_max' => [12.8],
                'wind_gusts_10m_max' => [21.7],
                'wind_direction_10m_dominant' => [278],
                'uv_index_max' => [4.2],
                'sunshine_duration' => [21_600]
              }
            }.to_json
          )
      end

      it 'handles nil values in hourly forecasts gracefully' do
        open_meteo = described_class.new(resort: resort)
        hourly     = open_meteo.hourly_forecasts

        expect(hourly.length).to eq(2)

        # First hour has nil values
        expect(hourly[0].temperature).to be_nil
        expect(hourly[0].apparent_temperature).to be_nil
        expect(hourly[0].humidity).to eq(0) # nil.to_i returns 0
        expect(hourly[0].precipitation_probability).to eq(0)
        expect(hourly[0].precipitation).to be_nil
        expect(hourly[0].snowfall).to be_nil
        expect(hourly[0].cloud_cover).to eq(0)
        expect(hourly[0].wind_speed).to be_nil
        expect(hourly[0].wind_gust).to be_nil
        expect(hourly[0].freezing_level).to be_nil
        expect(hourly[0].visibility).to be_nil

        # Second hour has valid values
        expect(hourly[1].temperature).to eq(45.0)
        expect(hourly[1].apparent_temperature).to eq(42.1)
        expect(hourly[1].humidity).to eq(65)
        expect(hourly[1].snowfall).to eq(0.5)
      end
    end
  end

  describe '#current_conditions' do
    context 'when API returns nil values in current data' do
      before do
        stub_request(:get, /api.open-meteo.com/)
          .to_return(
            status: 200,
            body: {
              'current' => {
                'time' => '2023-03-14T12:00',
                'temperature_2m' => nil,
                'relative_humidity_2m' => nil,
                'apparent_temperature' => nil,
                'is_day' => 1,
                'precipitation' => nil,
                'weather_code' => 2,
                'cloud_cover' => nil,
                'wind_speed_10m' => nil,
                'wind_direction_10m' => nil,
                'wind_gusts_10m' => nil
              },
              'hourly' => {
                'time' => ['2023-03-14T00:00'],
                'temperature_2m' => [45.0],
                'relative_humidity_2m' => [65],
                'apparent_temperature' => [42.1],
                'precipitation_probability' => [50],
                'precipitation' => [0.1],
                'snowfall' => [0.5],
                'weather_code' => [71],
                'cloud_cover' => [40],
                'wind_speed_10m' => [10.0],
                'wind_direction_10m' => [180],
                'wind_gusts_10m' => [20.0],
                'freezing_level_height' => [8000],
                'visibility' => [10_000],
                'is_day' => [1]
              },
              'daily' => {
                'time' => ['2023-03-14'],
                'weather_code' => [3],
                'temperature_2m_max' => [62.2],
                'temperature_2m_min' => [36.8],
                'apparent_temperature_max' => [58.3],
                'apparent_temperature_min' => [32.1],
                'snowfall_sum' => [0.0],
                'precipitation_sum' => [0.0],
                'rain_sum' => [0.0],
                'precipitation_hours' => [0.0],
                'precipitation_probability_max' => [5],
                'wind_speed_10m_max' => [12.8],
                'wind_gusts_10m_max' => [21.7],
                'wind_direction_10m_dominant' => [278],
                'uv_index_max' => [4.2],
                'sunshine_duration' => [21_600]
              }
            }.to_json
          )
      end

      it 'handles nil values in current conditions gracefully' do
        open_meteo = described_class.new(resort: resort)
        current    = open_meteo.current_conditions

        expect(current.temperature).to be_nil
        expect(current.apparent_temperature).to be_nil
        expect(current.humidity).to eq(0) # nil.to_i returns 0
        expect(current.precipitation).to be_nil
        expect(current.cloud_cover).to eq(0)
        expect(current.wind_speed).to be_nil
        expect(current.wind_gust).to be_nil
        expect(current.wind_direction).to eq(:N) # defaults to :N for nil
        expect(current.is_day).to be(true)
      end
    end
  end

  describe '#wind_direction' do
    before { stub_weather_api }

    it 'handles nil wind direction' do
      open_meteo = described_class.new(resort: resort)
      # Access the private method for testing
      direction  = open_meteo.send(:wind_direction, nil)
      expect(direction).to eq(:N)
    end

    it 'correctly maps degrees to cardinal directions' do
      open_meteo = described_class.new(resort: resort)

      expect(open_meteo.send(:wind_direction, 0)).to eq(:N)
      expect(open_meteo.send(:wind_direction, 45)).to eq(:NE)
      expect(open_meteo.send(:wind_direction, 90)).to eq(:E)
      expect(open_meteo.send(:wind_direction, 135)).to eq(:SE)
      expect(open_meteo.send(:wind_direction, 180)).to eq(:S)
      expect(open_meteo.send(:wind_direction, 225)).to eq(:SW)
      expect(open_meteo.send(:wind_direction, 270)).to eq(:W)
      expect(open_meteo.send(:wind_direction, 315)).to eq(:NW)
      expect(open_meteo.send(:wind_direction, 359)).to eq(:N)
    end
  end
end
