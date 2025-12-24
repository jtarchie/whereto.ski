# frozen_string_literal: true

require 'active_support'
require 'active_support/core_ext/string'

module FollowTheSnow
  Forecast::Daily = Struct.new(:forecasts, keyword_init: true) do
    class ForecastDelegate < SimpleDelegator
      def time_of_day
        __getobj__.time_of_day.strftime('%a %m/%d')
      end

      def snow
        case __getobj__.snow.begin
        when 0
          case __getobj__.snow.end
          when 0
            '<span class="imperial">0"</span><span class="metric">0 cm</span>'.html_safe
          else
            %(<span class="imperial">#{__getobj__.snow.end}"</span><span class="metric">#{inches_to_metric __getobj__.snow.end}</span>).html_safe
          end
        else
          %(<span class="imperial">#{__getobj__.snow.begin}-#{__getobj__.snow.end}"</span>).html_safe +
            %(<span class="metric">#{inches_to_metric __getobj__.snow.begin}-#{inches_to_metric __getobj__.snow.end}</span>).html_safe
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
        f = __getobj__.temp.end
        %(<span class="imperial">#{f} °F</span><span class="metric">#{fahrenheit_to_celsius f} °C</span>).html_safe
      end

      def apparent_temp
        f = __getobj__.apparent_temp.end
        %(<span class="imperial">#{f} °F</span><span class="metric">#{fahrenheit_to_celsius f} °C</span>).html_safe
      end

      def uv_index
        __getobj__.uv_index
      end

      def sunshine_duration
        # Convert seconds to hours and minutes for display
        total_seconds = __getobj__.sunshine_duration
        hours         = total_seconds / 3600
        minutes       = (total_seconds % 3600) / 60

        if hours.positive?
          "#{hours}h #{minutes}m"
        else
          "#{minutes}m"
        end
      end

      def precipitation_probability
        "#{__getobj__.precipitation_probability}%"
      end

      def wind_gust
        speed = __getobj__.wind_gust.end
        %(<span class="imperial">#{speed} mph</span><span class="metric">#{mph_to_kph speed} kph</span>).html_safe
      end

      def wind_speed
        speed = __getobj__.wind_speed.end
        %(#{__getobj__.wind_direction} <span class="imperial">#{speed} mph</span><span class="metric">#{mph_to_kph speed} kph</span>).html_safe
      end

      private

      def mph_to_kph(mph)
        kph = mph * 1.60934
        kph.round(2)
      end

      def fahrenheit_to_celsius(fahrenheit)
        celsius = (fahrenheit - 32) * 5.0 / 9.0
        celsius.round(2)
      end

      def inches_to_metric(inches)
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
      end
    end
  end
end
