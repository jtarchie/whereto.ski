# frozen_string_literal: true

require 'active_support/core_ext/string'

module FollowTheSnow
  module Builder
    # Helper module for snow-related calculations and formatting
    module SnowHelper
      # Convert inches to centimeters or millimeters
      def inches_to_metric(inches)
        cm_value = inches * 2.54

        # Use millimeters for values less than 1 cm
        if cm_value < 1.0
          mm_value = cm_value * 10
          "#{mm_value.round(2)} mm"
        else
          "#{cm_value.round(2)} cm"
        end
      end

      def format_snow_total(inches)
        snow_value(inches)
      end

      # Format snow total as plain text for meta descriptions (no HTML)
      def format_snow_total_plain(inches)
        return '0 inches' if inches.zero?

        imperial = if inches >= 1
                     "#{inches.round(1)} inches"
                   else
                     "#{(inches * 10).round(0) / 10.0} inches"
                   end

        metric = inches_to_metric(inches)

        "#{imperial} (#{metric})"
      end

      def snow?(value)
        snow_amount(value).positive?
      end

      # Cells are rendered snow tags; read the raw value, not the display text.
      def snow_amount(value)
        (value.to_s[/value="(-?[\d.]+)"/, 1] || value.to_s.gsub(/[^\d.-]/, '')).to_f
      end

      # Extract numeric snow value from forecast
      def snow_inches(forecast)
        return 0 if forecast.nil?

        snow = forecast.snow
        return 0 if snow.nil?

        if snow.respond_to?(:end)
          snow.end.to_f
        elsif snow.respond_to?(:to_f)
          snow.to_f
        else
          0
        end
      end

      # Get snow icon/indicator for display
      def snow_indicator
        %(<span class="snow-indicator" aria-label="Snow in forecast">❄️</span>).html_safe
      end
    end
  end
end
