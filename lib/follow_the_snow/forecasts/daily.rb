# frozen_string_literal: true

require 'active_support'
require 'active_support/core_ext/string'
require_relative '../builder/units'

module FollowTheSnow
  Forecast::Daily = Struct.new(:forecasts, keyword_init: true) do
    class ForecastDelegate < SimpleDelegator
      include Builder::Units

      # Check if this forecast has valid essential data
      # Returns false if critical fields are nil
      def valid?
        obj = __getobj__
        return false if obj.nil?
        return false if obj.time_of_day.nil?

        # Temperature is considered essential - if both min and max are nil, invalid
        temp_range = obj.temp
        return false if temp_range.nil?
        return false if temp_range.begin.nil? && temp_range.end.nil?

        true
      end

      def time_of_day
        __getobj__.time_of_day&.strftime('%a %m/%d') || 'N/A'
      end

      def snow
        snow_value(__getobj__.snow&.end)
      end

      def temp
        temp_value(__getobj__.temp&.end)
      end

      def apparent_temp
        temp_value(__getobj__.apparent_temp&.end)
      end

      def uv_index
        __getobj__.uv_index || '--'
      end

      def sunshine_duration
        # Convert seconds to hours and minutes for display
        total_seconds = __getobj__.sunshine_duration
        return '--' if total_seconds.nil?

        hours         = total_seconds / 3600
        minutes       = (total_seconds % 3600) / 60

        if hours.positive?
          "#{hours}h #{minutes}m"
        else
          "#{minutes}m"
        end
      end

      def precipitation_probability
        prob = __getobj__.precipitation_probability
        prob.nil? ? '--%' : "#{prob}%"
      end

      def wind_gust
        speed_value(__getobj__.wind_gust&.end)
      end

      def wind_speed
        "#{__getobj__.wind_direction} ".html_safe + speed_value(__getobj__.wind_speed&.end)
      end
    end

    def forecasts
      self['forecasts'].map do |forecast|
        ForecastDelegate.new(forecast)
      end.select(&:valid?)
    end
  end
end
