# frozen_string_literal: true

require 'http'
require 'json'

module FollowTheSnow
  class Forecast::OpenMeteo < Struct.new(:resort, keyword_init: true)
    # Guards the lazy fetch: pages render on many threads sharing one client.
    def initialize(**)
      super
      @fetch_mutex = Mutex.new
    end

    API_URL       = ENV.fetch('OPEN_METEO_API_URL', 'https://api.open-meteo.com')
    # Built once: these run for every hour of every resort.
    WEATHER_CODES = {
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
    }.freeze

    HOURLY_COLUMNS = %w[temperature_2m
                        apparent_temperature
                        relative_humidity_2m
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
                        is_day].freeze

    WIND_DIRECTIONS = %i[N NNE NE ENE E ESE SE SSE S SSW SW WSW W WNW NW NNW].freeze

    MAX_ATTEMPTS = 5

    class ApiError < StandardError
    end

    class RetryableError < StandardError
    end

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
      snow_depth
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

    PAST_DAYS = 3

    # Summit is primary: it's where resorts measure and where most snow falls.
    def forecasts
      @forecasts ||= upcoming_days(parse_daily_forecasts(summit_data))
    end

    def hourly_forecasts
      @hourly_forecasts ||= summit_hours.select { |h| h.time >= now }
    end

    def current_conditions
      @current_conditions ||= parse_current_conditions
    end

    def base_forecasts
      return forecasts unless base_data

      @base_forecasts ||= upcoming_days(parse_daily_forecasts(base_data))
    end

    def base_hourly_forecasts
      return hourly_forecasts unless base_data

      @base_hourly_forecasts ||= parse_hourly_forecasts(base_data).select { |h| h.time >= now }
    end

    def past_snowfall(hours: 72)
      summit_hours
        .select { |h| h.time < now && h.time >= now - (hours * 3600) }
        .sum { |h| h.snowfall.to_f }
        .round(2)
    end

    # Imperial requests get depth in feet, but every snow value here is inches.
    def snow_depth
      feet = hourly_forecasts.first&.snow_depth
      feet && (feet * 12).round(1)
    end

    def timezone
      summit_data.fetch('timezone', 'UTC')
    end

    def now
      @now ||= begin
        current = local_time(summit_data.fetch('current').fetch('time'), summit_data)
        current - (current.min * 60)
      end
    end

    private

    def summit_data
      fetch_data.last
    end

    def summit_hours
      @summit_hours ||= parse_hourly_forecasts(summit_data)
    end

    def base_data
      fetch_data.first if fetch_data.length > 1
    end

    def upcoming_days(days)
      days.reject { |d| d.time_of_day < now.to_date }
    end

    def local_time(timestamp, data)
      year, month, day, hour, minute = timestamp.scan(/\d+/).map(&:to_i)
      Time.new(year, month, day, hour || 0, minute || 0, 0, data.fetch('utc_offset_seconds', 0))
    end

    def request_params
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
        timezone: 'auto',
        past_days: PAST_DAYS,
        forecast_days: 16,
        apikey: ENV.fetch('OPEN_METEO_API_KEY', nil)
      }

      # Base + summit as two locations in one request; elevations are meters.
      if resort.min_elevation && resort.max_elevation
        params[:latitude]  = [resort.lat, resort.lat].join(',')
        params[:longitude] = [resort.lon, resort.lon].join(',')
        params[:elevation] = [resort.min_elevation, resort.max_elevation].map { |e| e.to_f.round }.join(',')
      end

      params.compact
    end

    def fetch_data
      @fetch_mutex.synchronize { @fetch_data ||= fetch_data_uncached }
    end

    def fetch_data_uncached
      attempts = 0
      begin
        attempts += 1
        response  = HTTP.timeout(10).get("#{API_URL}/v1/forecast", params: request_params)
        payload   = JSON.parse(response.to_s)
        locations = payload.is_a?(Array) ? payload : [payload]
        locations.each { |location| check_error!(response.code, location) }
        locations
      rescue JSON::ParserError, OpenSSL::SSL::SSLError, HTTP::Error, RetryableError => e
        raise ApiError, "Resort ID #{resort&.id || 'N/A'}: gave up after #{attempts} attempts: #{e.message}" if attempts >= MAX_ATTEMPTS

        warn "[API ERROR] Resort ID #{resort&.id || 'N/A'}: #{e.class} - #{e.message}. Retrying after sleep..."
        sleep((2**attempts) + rand) # exponential backoff + jitter
        retry
      end
    end

    # Invalid keys and bad params never recover, so only 429/5xx are retried.
    def check_error!(status, payload)
      # Non-object payload (null, string, number) is a proxy/CDN glitch: retry like a 5xx.
      raise RetryableError, "unexpected payload: #{payload.inspect[0, 80]}" unless payload.is_a?(Hash)

      return unless payload['error'] || !payload.key?('daily')

      reason = payload['reason'] || "HTTP #{status}, no daily data"
      raise RetryableError, reason if status == 429 || status >= 500

      raise ApiError, "Resort ID #{resort&.id || 'N/A'}: Open-Meteo error: #{reason}"
    end

    def parse_daily_forecasts(data)
      daily = data.fetch('daily')

      daily.fetch('time').each_with_index.map do |timestamp, index|
        dt                    = Date.parse(timestamp)
        temp_range            = (daily.fetch('temperature_2m_min')[index]&.round(2))..(daily['temperature_2m_max'][index]&.round(2))
        apparent_temp_range   = (daily.fetch('apparent_temperature_min')[index]&.round(2))..(daily['apparent_temperature_max'][index]&.round(2))
        snow_range            = 0..(daily.fetch('snowfall_sum')[index]&.round(2) || 0)
        wind_gust_range       = 0..(daily.fetch('wind_gusts_10m_max')[index]&.round(2) || 0)
        wind_speed_range      = 0..(daily.fetch('wind_speed_10m_max')[index]&.round(2) || 0)
        uv_max                = daily.fetch('uv_index_max')[index]&.round(1)
        sunshine_secs         = daily.fetch('sunshine_duration')[index]&.to_i
        precip_prob           = daily.fetch('precipitation_probability_max')[index]&.to_i
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

    def parse_hourly_forecasts(data)
      hourly     = data.fetch('hourly')
      col        = HOURLY_COLUMNS.to_h { |key| [key, hourly.fetch(key)] }
      times      = hourly.fetch('time')
      snow_depth = hourly.fetch('snow_depth', [])
      # Open-Meteo hourly series are consecutive hours, so only the first timestamp needs parsing.
      start      = times.first && local_time(times.first, data)

      times.each_index.map do |i|
        HourlyForecast.new(
          time: start + (i * 3600),
          snow_depth: snow_depth[i],
          temperature: col['temperature_2m'][i]&.round(1),
          apparent_temperature: col['apparent_temperature'][i]&.round(1),
          humidity: col['relative_humidity_2m'][i]&.to_i,
          precipitation_probability: col['precipitation_probability'][i]&.to_i,
          precipitation: col['precipitation'][i]&.round(2),
          snowfall: col['snowfall'][i]&.round(2),
          weather_code: col['weather_code'][i],
          weather_description: weather_codes(col['weather_code'][i]),
          cloud_cover: col['cloud_cover'][i]&.to_i,
          wind_speed: col['wind_speed_10m'][i]&.round(1),
          wind_direction: wind_direction(col['wind_direction_10m'][i]),
          wind_gust: col['wind_gusts_10m'][i]&.round(1),
          freezing_level: col['freezing_level_height'][i]&.round(0),
          visibility: col['visibility'][i]&.round(0),
          is_day: col['is_day'][i] == 1
        )
      end
    end

    def parse_current_conditions
      current = summit_data.fetch('current')

      CurrentConditions.new(
        temperature: current.fetch('temperature_2m')&.round(1),
        apparent_temperature: current.fetch('apparent_temperature')&.round(1),
        humidity: current.fetch('relative_humidity_2m')&.to_i,
        weather_code: current.fetch('weather_code'),
        weather_description: weather_codes(current.fetch('weather_code')),
        cloud_cover: current.fetch('cloud_cover')&.to_i,
        wind_speed: current.fetch('wind_speed_10m')&.round(1),
        wind_direction: wind_direction(current.fetch('wind_direction_10m')),
        wind_gust: current.fetch('wind_gusts_10m')&.round(1),
        precipitation: current.fetch('precipitation')&.round(2),
        is_day: current.fetch('is_day') == 1,
        time: local_time(current.fetch('time'), summit_data)
      )
    end

    def weather_codes(code)
      WEATHER_CODES[code] || ''
    end

    def wind_direction(degree)
      return :N if degree.nil?

      WIND_DIRECTIONS[(degree % 360 / 22.5).round % 16]
    end
  end
end
