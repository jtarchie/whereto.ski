# frozen_string_literal: true

module FollowTheSnow
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
    keyword_init: true
  )
end

require_relative 'forecasts/daily'
require_relative 'forecasts/open_meteo'
