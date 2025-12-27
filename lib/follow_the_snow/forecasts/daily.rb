# frozen_string_literal: true

require 'active_support'
require 'active_support/core_ext/string'

module FollowTheSnow
  Forecast::Daily = Struct.new(:forecasts, keyword_init: true) do
    class ForecastDelegate < SimpleDelegator
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
        snow_range = __getobj__.snow
        return '<span class="imperial">0"</span><span class="metric">0 cm</span>'.html_safe if snow_range.nil?

        snow_begin = snow_range.begin || 0
        snow_end   = snow_range.end || 0

        case snow_begin
        when 0
          case snow_end
          when 0
            '<span class="imperial">0"</span><span class="metric">0 cm</span>'.html_safe
          else
            %(<span class="imperial">#{snow_end}"</span><span class="metric">#{inches_to_metric snow_end}</span>).html_safe
          end
        else
          %(<span class="imperial">#{snow_begin}-#{snow_end}"</span>).html_safe +
            %(<span class="metric">#{inches_to_metric snow_begin}-#{inches_to_metric snow_end}</span>).html_safe
        end
      end

      def short_icon
        case short
        when /Snow/i
          '❄️'
        when /Sunny/i
          '☀️'
        when /Cloud/i
          '☁️'
        else
          '⛅️'
        end
      end

      def temp
        f = __getobj__.temp&.end
        return '<span class="imperial">--°F</span><span class="metric">--°C</span>'.html_safe if f.nil?

        %(<span class="imperial">#{f} °F</span><span class="metric">#{fahrenheit_to_celsius f} °C</span>).html_safe
      end

      def apparent_temp
        f = __getobj__.apparent_temp&.end
        return '<span class="imperial">--°F</span><span class="metric">--°C</span>'.html_safe if f.nil?

        %(<span class="imperial">#{f} °F</span><span class="metric">#{fahrenheit_to_celsius f} °C</span>).html_safe
      end

      def uv_index
        __getobj__.uv_index || '--'
      end

      def sunshine_duration
        # Convert seconds to hours and minutes for display
        total_seconds = __getobj__.sunshine_duration || 0
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
        speed = __getobj__.wind_gust&.end
        return '<span class="imperial">-- mph</span><span class="metric">-- kph</span>'.html_safe if speed.nil?

        %(<span class="imperial">#{speed} mph</span><span class="metric">#{mph_to_kph speed} kph</span>).html_safe
      end

      def wind_speed
        speed     = __getobj__.wind_speed&.end
        direction = __getobj__.wind_direction || ''
        return %(#{direction} <span class="imperial">-- mph</span><span class="metric">-- kph</span>).html_safe if speed.nil?

        %(#{direction} <span class="imperial">#{speed} mph</span><span class="metric">#{mph_to_kph speed} kph</span>).html_safe
      end

      private

      def mph_to_kph(mph)
        return 0 if mph.nil?

        kph = mph * 1.60934
        kph.round(2)
      end

      def fahrenheit_to_celsius(fahrenheit)
        return nil if fahrenheit.nil?

        celsius = (fahrenheit - 32) * 5.0 / 9.0
        celsius.round(2)
      end

      def inches_to_metric(inches)
        return '0 cm' if inches.nil? || inches.zero?

        # Conversion factor: 1 inch = 2.54 centimeters
        cm_value = inches * 2.54

        # Define the threshold
        threshold = 1.0

        return "#{cm_value.round(2)} cm" unless cm_value < threshold

        # Convert to millimeters (1 cm = 10 mm)
        mm_value = cm_value * 10
        "#{mm_value.round(2)} mm"
      end
    end

    def forecasts
      self['forecasts'].map do |forecast|
        ForecastDelegate.new(forecast)
      end.select(&:valid?)
    end
  end
end
