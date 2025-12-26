# frozen_string_literal: true

require 'http'
require 'json'

module FollowTheSnow
  Forecast::OpenMeteo = Struct.new(:resort, keyword_init: true) do
    API_URL = ENV.fetch('OPEN_METEO_API_URL', 'https://api.open-meteo.com')

    HOURLY_PARAMS = %w[
      temperature_2m
      relative_humidity_2m
      apparent_temperature
      precipitation_probability
      precipitation
      snowfall
      weather_code
      cloud_cover
      wind_speed_10m
      wind_direction_10m
      wind_gusts_10m
      freezing_level_height
      visibility
      is_day
    ].freeze

    DAILY_PARAMS = %w[
      weather_code
      temperature_2m_max
      temperature_2m_min
      apparent_temperature_max
      apparent_temperature_min
      sunrise
      sunset
      snowfall_sum
      precipitation_sum
      rain_sum
      precipitation_hours
      precipitation_probability_max
      wind_speed_10m_max
      wind_gusts_10m_max
      wind_direction_10m_dominant
      uv_index_max
      sunshine_duration
    ].freeze

    CURRENT_PARAMS = %w[
      temperature_2m
      relative_humidity_2m
      apparent_temperature
      is_day
      precipitation
      weather_code
      cloud_cover
      wind_speed_10m
      wind_direction_10m
      wind_gusts_10m
    ].freeze

    def forecasts
      @forecasts ||= parse_daily_forecasts
    end

    def hourly_forecasts
      @hourly_forecasts ||= parse_hourly_forecasts
    end

    def current_conditions
      @current_conditions ||= parse_current_conditions
    end

    private

    def fetch_data
      @fetch_data ||= begin
        params = {
          latitude: resort.lat,
          longitude: resort.lon,
          models: 'best_match',
          hourly: HOURLY_PARAMS.join(','),
          daily: DAILY_PARAMS.join(','),
          current: CURRENT_PARAMS.join(','),
          temperature_unit: 'fahrenheit',
          wind_speed_unit: 'mph',
          precipitation_unit: 'inch',
          timezone: 'America/New_York',
          forecast_days: 16,
          apikey: ENV.fetch('OPEN_METEO_API_KEY', nil)
        }.compact

        JSON.parse(
          HTTP.timeout(10).get("#{API_URL}/v1/forecast", params: params)
        )
      rescue JSON::ParserError, OpenSSL::SSL::SSLError, HTTP::Error, KeyError => e
        warn "[API ERROR] Resort ID #{resort&.id || 'N/A'}: #{e.class} - #{e.message}. Retrying after sleep..."
        sleep(rand(5))
        retry
      end
    end

    def parse_daily_forecasts
      daily = fetch_data.fetch('daily')

      daily.fetch('time').each_with_index.map do |timestamp, index|
        dt                    = Date.parse(timestamp)
        temp_range            = (daily.fetch('temperature_2m_min')[index]&.round(2))..(daily['temperature_2m_max'][index]&.round(2))
        apparent_temp_range   = (daily.fetch('apparent_temperature_min')[index]&.round(2))..(daily['apparent_temperature_max'][index]&.round(2))
        snow_range            = 0..(daily.fetch('snowfall_sum')[index]&.round(2) || 0)
        wind_gust_range       = 0..(daily.fetch('wind_gusts_10m_max')[index]&.round(2) || 0)
        wind_speed_range      = 0..(daily.fetch('wind_speed_10m_max')[index]&.round(2) || 0)
        uv_max                = daily.fetch('uv_index_max')[index]&.round(1)
        sunshine_secs         = daily.fetch('sunshine_duration')[index].to_i
        precip_prob           = daily.fetch('precipitation_probability_max')[index].to_i
        precip_sum            = daily.fetch('precipitation_sum')[index].to_f.round(2)
        rain_sum              = daily.fetch('rain_sum')[index].to_f.round(2)

        Forecast.new(
          name: dt.strftime('%a %m/%d'),
          short: weather_codes(daily.fetch('weather_code')[index]),
          snow: snow_range,
          temp: temp_range,
          apparent_temp: apparent_temp_range,
          time_of_day: dt,
          wind_direction: wind_direction(daily.fetch('wind_direction_10m_dominant')[index]),
          wind_gust: wind_gust_range,
          wind_speed: wind_speed_range,
          uv_index: uv_max,
          sunshine_duration: sunshine_secs,
          precipitation_probability: precip_prob,
          precipitation: precip_sum,
          rain: rain_sum
        )
      end
    end

    def parse_hourly_forecasts
      hourly = fetch_data.fetch('hourly')

      hourly.fetch('time').each_with_index.map do |timestamp, index|
        time = Time.parse(timestamp)

        HourlyForecast.new(
          time: time,
          temperature: hourly.fetch('temperature_2m')[index]&.round(1),
          apparent_temperature: hourly.fetch('apparent_temperature')[index]&.round(1),
          humidity: hourly.fetch('relative_humidity_2m')[index].to_i,
          precipitation_probability: hourly.fetch('precipitation_probability')[index].to_i,
          precipitation: hourly.fetch('precipitation')[index]&.round(2),
          snowfall: hourly.fetch('snowfall')[index]&.round(2),
          weather_code: hourly.fetch('weather_code')[index],
          weather_description: weather_codes(hourly.fetch('weather_code')[index]),
          cloud_cover: hourly.fetch('cloud_cover')[index].to_i,
          wind_speed: hourly.fetch('wind_speed_10m')[index]&.round(1),
          wind_direction: wind_direction(hourly.fetch('wind_direction_10m')[index]),
          wind_gust: hourly.fetch('wind_gusts_10m')[index]&.round(1),
          freezing_level: hourly.fetch('freezing_level_height')[index]&.round(0),
          visibility: hourly.fetch('visibility')[index]&.round(0),
          is_day: hourly.fetch('is_day')[index] == 1
        )
      end
    end

    def parse_current_conditions
      current = fetch_data.fetch('current')

      CurrentConditions.new(
        temperature: current.fetch('temperature_2m')&.round(1),
        apparent_temperature: current.fetch('apparent_temperature')&.round(1),
        humidity: current.fetch('relative_humidity_2m').to_i,
        weather_code: current.fetch('weather_code'),
        weather_description: weather_codes(current.fetch('weather_code')),
        cloud_cover: current.fetch('cloud_cover').to_i,
        wind_speed: current.fetch('wind_speed_10m')&.round(1),
        wind_direction: wind_direction(current.fetch('wind_direction_10m')),
        wind_gust: current.fetch('wind_gusts_10m')&.round(1),
        precipitation: current.fetch('precipitation')&.round(2),
        is_day: current.fetch('is_day') == 1,
        time: Time.parse(current.fetch('time'))
      )
    end

    def weather_codes(code)
      {
        0 => 'Clear sky',
        1 => 'Mainly clear',
        2 => 'Partly cloudy',
        3 => 'Overcast',
        45 => 'Fog',
        48 => 'Depositing rime fog',
        51 => 'Drizzle: Light intensity',
        53 => 'Drizzle: Moderate intensity',
        55 => 'Drizzle: Dense intensity',
        56 => 'Freezing Drizzle: Light intensity',
        57 => 'Freezing Drizzle: Dense intensity',
        61 => 'Rain: Slight intensity',
        63 => 'Rain: Moderate intensity',
        65 => 'Rain: Heavy intensity',
        66 => 'Freezing Rain: Light intensity',
        67 => 'Freezing Rain: Heavy intensity',
        71 => 'Snow fall: Slight intensity',
        73 => 'Snow fall: Moderate intensity',
        75 => 'Snow fall: Heavy intensity',
        77 => 'Snow grains',
        80 => 'Rain showers: Slight intensity',
        81 => 'Rain showers: Moderate intensity',
        82 => 'Rain showers: Violent intensity',
        85 => 'Snow showers: Slight intensity',
        86 => 'Snow showers: Heavy intensity',
        95 => 'Thunderstorm: Slight or moderate',
        96 => 'Thunderstorm with slight hail',
        99 => 'Thunderstorm with heavy hail'
      }[code] || ''
    end

    def wind_direction(degree)
      return :N if degree.nil?

      directions = {
        N: [348.75..360, 0..11.25],
        NNE: [11.25..33.75],
        NE: [33.75..56.25],
        ENE: [56.25..78.75],
        E: [78.75..101.25],
        ESE: [101.25..123.75],
        SE: [123.75..146.25],
        SSE: [146.25..168.75],
        S: [168.75..191.25],
        SSW: [191.25..213.75],
        SW: [213.75..236.25],
        WSW: [236.25..258.75],
        W: [258.75..281.25],
        WNW: [281.25..303.75],
        NW: [303.75..326.25],
        NNW: [326.25..348.75]
      }

      directions.find do |_direction, degrees|
        degrees.any? do |range|
          range.include?(degree)
        end
      end&.first || :N
    end
  end
end
