# frozen_string_literal: true

require 'active_support/core_ext/string'
require 'erb'

module FollowTheSnow
  module Builder
    # data-k kinds (s in, t °F, w mph, h ft, d km) are reformatted by pages/input.js; text is the no-JS default.
    module Units
      def snow_value(inches)
        inches = inches.to_f
        value_tag(inches.round(2), 's', "#{compact(inches)}″")
      end

      def temp_value(fahrenheit)
        return '–' if fahrenheit.nil?

        value_tag(fahrenheit.round(1), 't', "#{fahrenheit.round}°F")
      end

      def speed_value(mph)
        return '–' if mph.nil?

        value_tag(mph.round(1), 'w', "#{mph.round} mph")
      end

      def height_value(feet)
        return '–' if feet.nil?

        value_tag(feet.round, 'h', "#{group(feet.round)} ft")
      end

      def distance_value(kilometers)
        return '–' if kilometers.nil?

        value_tag(kilometers.round(1), 'd', "#{(kilometers * 0.621371).round} mi")
      end

      # Instant in UTC for the client; default text in the zone the time was built in.
      def time_value(time, format: :hour)
        text = format == :hour ? time.strftime('%-l %p') : time.strftime('%a %b %-d, %-l:%M %p %Z')
        %(<time datetime="#{time.getutc.iso8601}" data-k="#{format == :hour ? 'hr' : 'dt'}">#{ERB::Util.h(text)}</time>).html_safe
      end

      def snow_level(inches)
        case inches.to_f
        when 0 then 0
        when 0...1 then 1
        when 1...2 then 2
        when 2...6 then 3
        when 6...12 then 4
        else 5
        end
      end

      private

      def value_tag(raw, kind, text)
        %(<data value="#{raw}" data-k="#{kind}">#{text}</data>).html_safe
      end

      # Matches the client: one decimal under 10, whole numbers above.
      def compact(number)
        return number.round if number.abs >= 10

        rounded = number.round(1)
        rounded == rounded.to_i ? rounded.to_i : rounded
      end

      def group(number)
        number.to_s.reverse.scan(/\d{1,3}/).join(',').reverse.then { |s| number.negative? ? "-#{s}" : s }
      end
    end
  end
end
