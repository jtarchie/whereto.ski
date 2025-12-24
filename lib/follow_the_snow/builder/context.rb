# frozen_string_literal: true

require 'active_support/time'
require 'active_support/core_ext/string'
require_relative 'snow_helper'

module FollowTheSnow
  module Builder
    class Context
      include ERB::Util
      include SnowHelper

      # Countries with this many or fewer resorts will show resorts directly
      # instead of states/regions, to simplify navigation
      SMALL_COUNTRY_THRESHOLD = 20

      attr_reader :resorts

      def initialize(resorts:)
        @resorts = resorts.sort_by do |r|
          [r.country_code, r.region_code, r.name].join
        end
      end

      def resorts_by_countries
        @resorts_by_countries ||= @resorts.group_by(&:country_name)
      end

      def countries
        resorts_by_countries.keys.sort
      end

      def states(country:)
        resorts_by_countries.fetch(country).group_by(&:region_name).keys
      end

      # Check if a country should skip state/region pages and show resorts directly
      def small_country?(country)
        resorts_for_country(country).count <= SMALL_COUNTRY_THRESHOLD
      end

      # Check if a country has any snow in the forecast
      def country_has_snow?(country)
        resorts_by_countries.fetch(country).any? do |resort|
          any_snow?(resort)
        end
      end

      # Check if a state/region has any snow in the forecast
      def state_has_snow?(state)
        resorts = @resorts.select { |r| r.region_name == state }
        resorts.any? { |resort| any_snow?(resort) }
      end

      # Get total snow amount for a country
      def total_snow_for_country(country)
        resorts_by_countries.fetch(country).sum do |resort|
          total_snow_for(resort)
        end
      end

      # Get total snow amount for a state/region
      def total_snow_for_state(state)
        resorts = @resorts.select { |r| r.region_name == state }
        resorts.sum { |resort| total_snow_for(resort) }
      end

      # Get count of resorts with snow in a country
      def country_snow_count(country)
        resorts_by_countries.fetch(country).count do |resort|
          any_snow?(resort)
        end
      end

      # Get count of resorts with snow in a state
      def state_snow_count(state)
        resorts = @resorts.select { |r| r.region_name == state }
        resorts.count { |resort| any_snow?(resort) }
      end

      # Get top N resorts by total snow in forecast period
      def top_snowy_resorts(limit: 10, country: nil, state: nil)
        resorts_to_check = filter_resorts(country: country, state: state)

        resort_snow = resorts_to_check.map do |resort|
          total = total_snow_for(resort)
          { resort: resort, total: total }
        end

        resort_snow.select { |rs| rs[:total].positive? }
                   .sort_by { |rs| -rs[:total] }
                   .take(limit)
      end

      # Get resorts with snow today (next 24 hours)
      def resorts_with_snow_today(limit: 10, country: nil, state: nil)
        resorts_to_check = filter_resorts(country: country, state: state)

        resort_snow = resorts_to_check.map do |resort|
          first_forecast = raw_forecasts_for(resort).first
          snow_amount    = first_forecast ? snow_inches(first_forecast) : 0
          { resort: resort, snow: snow_amount }
        end

        resort_snow.select { |rs| rs[:snow].positive? }
                   .sort_by { |rs| -rs[:snow] }
                   .take(limit)
      end

      # Get regional summaries (country -> total snow, resort count)
      def regional_summaries(country: nil)
        if country
          # Return state-level summaries for a specific country
          country_resorts = resorts_by_countries.fetch(country)
          country_resorts.group_by(&:region_name).map do |state, resorts|
            total_snow   = resorts.sum { |resort| total_snow_for(resort) }
            resort_count = resorts.count { |resort| any_snow?(resort) }

            {
              state: state,
              total_snow: total_snow,
              resort_count: resort_count,
              total_resorts: resorts.count
            }
          end.select { |s| s[:resort_count].positive? }
                         .sort_by { |s| -s[:total_snow] }
        else
          # Return country-level summaries
          resorts_by_countries.map do |country_name, resorts|
            total_snow = resorts.sum do |resort|
              total_snow_for(resort)
            end

            resort_count = resorts.count do |resort|
              any_snow?(resort)
            end

            {
              country: country_name,
              total_snow: total_snow,
              resort_count: resort_count,
              total_resorts: resorts.count
            }
          end.select { |s| s[:resort_count].positive? }
                              .sort_by { |s| -s[:total_snow] }
        end
      end

      # Get all resorts for a country
      def resorts_for_country(country)
        resorts_by_countries.fetch(country)
      end

      def table_for_resorts(resorts)
        max_days = resorts.map do |resort|
          resort.forecasts.map(&:time_of_day)
        end.max_by(&:length)

        headers  = ['Location'] + max_days

        rows = resorts.map do |resort|
          snow_days = resort.forecasts.map do |f|
            f.snow.to_s
          end

          row  = [%(<a href="/resorts/#{resort.slug}">#{resort.name}</a>).html_safe]
          row += if snow_days.length == max_days.length
                   snow_days
                 else
                   snow_days + ([''] * (max_days.length - snow_days.length))
                 end
          row
        end

        [headers, rows]
      end

      def table_for_longterm(resort)
        headers = ['Date', 'Snowfall', 'Icon', 'Conditions', 'Temp', 'Feels Like', 'UV Index', 'Sunshine', 'Precip %', 'Wind Speed', 'Wind Gusts']

        forecasts = resort.forecasts(
          aggregates: [FollowTheSnow::Forecast::Daily]
        )

        rows = forecasts.map do |f|
          [
            f.name,
            f.snow,
            f.short_icon,
            f.short,
            f.temp,
            f.apparent_temp,
            f.uv_index,
            f.sunshine_duration,
            f.precipitation_probability,
            f.wind_speed,
            f.wind_gust
          ]
        end

        [headers, rows]
      end

      # Get current conditions for a resort
      def current_conditions_for(resort)
        resort.current_conditions
      end

      # Get hourly forecasts for a resort (next 48 hours by default)
      def hourly_forecasts_for(resort, hours: 48)
        resort.hourly_forecasts.take(hours)
      end

      # Get weather icon based on weather code
      def weather_icon(code, is_day: true)
        case code
        when 0 # Clear sky
          is_day ? '☀️' : '🌙'
        when 1, 2 # Mainly clear, partly cloudy
          is_day ? '⛅' : '☁️'
        when 3 # Overcast
          '☁️'
        when 45, 48 # Fog
          '🌫️'
        when 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82 # Drizzle and Rain
          '🌧️'
        when 71, 73, 75, 77, 85, 86 # Snow
          '❄️'
        when 95, 96, 99 # Thunderstorm
          '⛈️'
        else
          '🌤️'
        end
      end

      # Format temperature with imperial/metric toggle support
      def format_temperature(fahrenheit)
        return '-' if fahrenheit.nil?

        celsius = ((fahrenheit - 32) * 5.0 / 9.0).round(1)
        %(<span class="imperial">#{fahrenheit}°F</span><span class="metric">#{celsius}°C</span>).html_safe
      end

      # Format wind speed with direction
      def format_wind(speed, direction, gust: nil)
        return '-' if speed.nil?

        kph    = (speed * 1.60934).round(1)
        result = %(#{direction} <span class="imperial">#{speed} mph</span><span class="metric">#{kph} kph</span>)

        if gust && gust > speed
          gust_kph = (gust * 1.60934).round(1)
          result  += %( (gusts <span class="imperial">#{gust} mph</span><span class="metric">#{gust_kph} kph</span>))
        end

        result.html_safe
      end

      # Format elevation/height in feet and meters
      def format_elevation(feet)
        return '-' if feet.nil?

        meters = (feet * 0.3048).round(0)
        %(<span class="imperial">#{feet.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} ft</span><span class="metric">#{meters.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} m</span>).html_safe
      end

      # Format visibility
      def format_visibility(meters)
        return '-' if meters.nil?

        miles = (meters / 1609.34).round(1)
        km    = (meters / 1000.0).round(1)
        %(<span class="imperial">#{miles} mi</span><span class="metric">#{km} km</span>).html_safe
      end

      # Format precipitation amount
      def format_precipitation(inches)
        return '-' if inches.nil? || inches.zero?

        mm = (inches * 25.4).round(1)
        %(<span class="imperial">#{inches}"</span><span class="metric">#{mm} mm</span>).html_safe
      end

      # Format time for hourly display
      def format_hour(time)
        time.strftime('%I %p').gsub(/^0/, '')
      end

      # Format snowfall for display
      def format_snowfall(inches)
        return '-' if inches.nil? || inches.zero?

        cm = (inches * 2.54).round(1)
        %(<span class="imperial">#{inches}"</span><span class="metric">#{cm} cm</span>).html_safe
      end

      def current_timestamp
        Time.zone = 'Eastern Time (US & Canada)'
        Time.zone.now.strftime('%Y-%m-%d %l:%M%p %Z')
      end

      # Check if a resort has any snow in its forecast
      def any_snow?(resort)
        raw_forecasts_for(resort).any? do |forecast|
          snow_inches(forecast).positive?
        end
      end

      # Get total snow amount for a specific resort
      def total_snow_for(resort)
        raw_forecasts_for(resort).sum do |forecast|
          snow_inches(forecast)
        end
      end

      private

      # Filter resorts by country and/or state
      def filter_resorts(country: nil, state: nil)
        filtered = @resorts

        filtered = filtered.select { |r| r.country_name == country } if country
        filtered = filtered.select { |r| r.region_name == state } if state

        filtered
      end

      def raw_forecasts_for(resort)
        @raw_forecast_cache            ||= {}
        cache_key                        = resort.id || resort.object_id
        @raw_forecast_cache[cache_key] ||= resort.forecasts(aggregates: [])
      end
    end
  end
end
