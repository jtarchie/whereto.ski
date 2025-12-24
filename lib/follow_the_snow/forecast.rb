# frozen_string_literal: true

module FollowTheSnow
  # Daily forecast data
  Forecast = Struct.new(
    :name,
    :short,
    :snow,
    :temp,
    :apparent_temp,
    :time_of_day,
    :wind_direction,
    :wind_gust,
    :wind_speed,
    :uv_index,
    :sunshine_duration,
    :precipitation_probability,
    :humidity,
    :cloud_cover,
    :freezing_level,
    :precipitation,
    :rain,
    keyword_init: true
  )

  # Hourly forecast data
  HourlyForecast = Struct.new(
    :time,
    :temperature,
    :apparent_temperature,
    :humidity,
    :precipitation_probability,
    :precipitation,
    :snowfall,
    :weather_code,
    :weather_description,
    :cloud_cover,
    :wind_speed,
    :wind_direction,
    :wind_gust,
    :freezing_level,
    :visibility,
    :is_day,
    keyword_init: true
  )

  # Current conditions data
  CurrentConditions = Struct.new(
    :temperature,
    :apparent_temperature,
    :humidity,
    :weather_code,
    :weather_description,
    :cloud_cover,
    :wind_speed,
    :wind_direction,
    :wind_gust,
    :precipitation,
    :is_day,
    :time,
    keyword_init: true
  )
end

require_relative 'forecasts/daily'
require_relative 'forecasts/open_meteo'
