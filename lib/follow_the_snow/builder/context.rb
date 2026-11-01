# frozen_string_literal: true

require 'active_support/time'
require 'active_support/core_ext/string'
require 'tilt'
require 'tilt/erb'
require_relative 'snow_helper'
require_relative 'units'

module FollowTheSnow
  module Builder
    class Context
      include ERB::Util
      include SnowHelper
      include Units

      # Countries with this many or fewer resorts will show resorts directly
      # instead of states/regions, to simplify navigation
      SMALL_COUNTRY_THRESHOLD = 20
      NEARBY_KM               = 150
      SNOW_DAY                = 2
      POWDER_DAY              = 6
      OUTLOOK_LABELS          = {
        snow: ['Snow to base', false],
        mixed: ['Rain at base', true],
        rain: ['Rain to summit', true],
        dry: ['Dry', false]
      }.freeze

      attr_reader :resorts

      def initialize(resorts:, source_dir: File.expand_path('../../../pages', __dir__))
        @source_dir = source_dir
        @resorts    = resorts.sort_by do |r|
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

      # Get all resorts for a country
      def resorts_for_country(country)
        resorts_by_countries.fetch(country)
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

      def format_temperature(fahrenheit)
        temp_value(fahrenheit)
      end

      def format_wind(speed, direction, gust: nil)
        return '–' if speed.nil?

        result  = "#{direction} ".html_safe + speed_value(speed)
        result += ' (gusts '.html_safe + speed_value(gust) + ')'.html_safe if gust && gust > speed
        result
      end

      def format_elevation(feet)
        height_value(feet)
      end

      def format_elevation_m(meters)
        meters && height_value(meters * 3.28084)
      end

      def format_hour(time)
        time_value(time, format: :hour)
      end

      def format_snowfall(inches)
        return '–' if inches.nil? || inches.zero?

        snow_value(inches)
      end

      def current_timestamp
        time_value(Time.now.utc, format: :datetime)
      end

      # Latitude prefilter (1.4° ≈ 155 km) skips haversine for almost every pair.
      def nearby_resorts(resort, limit: 8)
        @nearby                                ||= {}
        @nearby[resort.id || resort.object_id] ||= @resorts.filter_map do |other|
          next if other.equal?(resort) || (other.lat - resort.lat).abs > 1.4

          km = distance_km(resort, other)
          { resort: other, km: km.round } if km <= NEARBY_KM
        end.sort_by { |n| n[:km] }.first(limit)
      end

      def nearby_by_snow(resort)
        nearby_resorts(resort).map { |n| n.merge(next_7d: snow_summary(n[:resort])[:next_7d]) }
                              .sort_by { |n| [-n[:next_7d], n[:km]] }
      end

      # Only worth a detour when the difference is both relative and absolute.
      def more_snow_nearby(resort, nearby)
        mine = snow_summary(resort)[:next_7d]
        best = nearby.first
        best if best && best[:next_7d] >= mine * 2 && best[:next_7d] - mine >= 3
      end

      RUN_ORDER = %w[novice easy intermediate advanced expert freeride extreme].freeze

      def terrain_runs(resort)
        (resort.runs || {}).sort_by { |type, _| RUN_ORDER.index(type) || RUN_ORDER.length }
                           .map { |type, stat| [type.humanize, stat] }
      end

      def terrain_lifts(resort)
        (resort.lifts || {}).sort_by { |_, stat| -stat[:count].to_i }.map { |type, stat| [type.humanize, stat] }
      end

      def distance_km(from, to)
        rad  = Math::PI / 180
        dlat = (to.lat - from.lat) * rad
        dlon = (to.lon - from.lon) * rad
        h    = (Math.sin(dlat / 2)**2) + (Math.cos(from.lat * rad) * Math.cos(to.lat * rad) * (Math.sin(dlon / 2)**2))
        12_742 * Math.asin(Math.sqrt(h))
      end

      def snow_days(resort)
        raw_forecasts_for(resort).map { |f| { date: f.time_of_day, inches: snow_inches(f) } }
      end

      def day_callout(resort)
        best = snow_days(resort).max_by { |d| d[:inches] }
        return unless best && best[:inches] >= SNOW_DAY

        best.merge(label: best[:inches] >= POWDER_DAY ? 'Powder day' : 'Snow day')
      end

      def day_name(date, index)
        index.zero? ? 'Today' : date.strftime('%a %-d')
      end

      # Freezing level stands in for snow level, taken from the hours it's actually precipitating.
      def snow_or_rain(resort, days: 3)
        base_days = resort.base_forecasts
        levels    = resort.hourly_forecasts.group_by { |h| h.time.to_date }.transform_values do |hours|
          wet = hours.select { |h| h.precipitation.to_f.positive? }
          (wet.empty? ? hours : wet).filter_map(&:freezing_level).max
        end
        base_ft   = resort.min_elevation && (resort.min_elevation * 3.28084)
        summit_ft = resort.max_elevation && (resort.max_elevation * 3.28084)

        raw_forecasts_for(resort).first(days).each_with_index.map do |day, index|
          base   = base_days[index]
          level  = levels[day.time_of_day]
          precip = [day.precipitation.to_f, base&.precipitation.to_f].max

          {
            date: day.time_of_day,
            snow_level: level,
            base_temp: base_ft && base&.temp,
            summit_temp: day.temp,
            wind: day.wind_speed&.end,
            gust: day.wind_gust&.end,
            status: precip_status(precip, level, base_ft, summit_ft)
          }
        end
      end

      def precip_status(precip, level, base_ft, summit_ft)
        return :dry if precip < 0.01
        return :unknown if level.nil? || base_ft.nil?
        return :snow if level <= base_ft
        return :mixed if summit_ft.nil? || level < summit_ft

        :rain
      end

      # crumbs: [[label, href], ...]; the last one is the current page.
      def breadcrumbs(crumbs)
        items = crumbs.each_with_index.map do |(label, href), index|
          current = index == crumbs.length - 1
          link    = current ? %(<span aria-current="page">#{h label}</span>) : %(<a href="#{h href}">#{h label}</a>)
          %(<li class="flex shrink-0 items-center gap-2">#{%(<span aria-hidden="true">/</span>) unless index.zero?}#{link}</li>)
        end
        %(<nav aria-label="Breadcrumb" class="-mx-4 overflow-x-auto px-4 text-sm text-ink-2"><ol class="flex gap-2 whitespace-nowrap">#{items.join}</ol></nav>).html_safe
      end

      # Renders pages/_name.html.erb with this context as self.
      def partial(name, **locals)
        @partials       ||= {}
        @partials[name] ||= Tilt::ERBTemplate.new(File.join(@source_dir, "_#{name}.html.erb"), trim: true)
        @partials[name].render(self, locals).html_safe
      end

      # Default order: 7-day snow, then 16-day, then name for a stable tie-break.
      def ranked(resorts)
        resorts.sort_by do |resort|
          summary = snow_summary(resort)
          [-summary[:next_7d], -summary[:next_16d], resort.name]
        end
      end

      def next_snow_day(resort)
        snow_days(resort).find { |d| d[:inches] >= 1 }
      end

      # Empty-state link: the area whose best resort has the most 16-day snow, if any has snow at all.
      def snowiest_area(groups, except:)
        groups.except(except).map { |name, list| [name, list.map { |r| snow_summary(r)[:next_16d] }.max.to_f] }
              .select { |_, inches| inches.positive? }.max_by(&:last)&.first
      end

      def regions_of(country)
        resorts_for_country(country).group_by(&:region_name)
      end

      # Meta description for a ranked scope; leads with the numbers a searcher wants. list must be ranked.
      # where: "in Colorado", "worldwide".
      def scope_description(list, where)
        snowing = list.count { |r| snow_summary(r)[:next_7d].positive? }
        text    = "#{snowing} of #{list.size} ski #{'resort'.pluralize(list.size)} #{where} #{snowing == 1 ? 'has' : 'have'} snow in the next 7 days"
        text   += ". Most: #{list.first.name}, #{format_snow_total_plain(snow_summary(list.first)[:next_7d])}" if snowing.positive?
        "#{text}. 16-day snow forecasts, updated daily."
      end

      # Areas ranked like resorts: by their best resort's 7-day, then 16-day snow. Dry areas come back separately, A–Z.
      def area_rows(groups)
        rows         = groups.map do |name, list|
          top = ranked(list).first
          { name: name, total: list.size, snowing: list.count { |r| snow_summary(r)[:next_7d].positive? }, top: top, summary: snow_summary(top) }
        end
        snowing, dry = rows.partition { |row| row[:summary][:next_7d].positive? }
        [snowing.sort_by { |row| [-row[:summary][:next_7d], -row[:summary][:next_16d], row[:name]] }, dry.sort_by { |row| row[:name] }]
      end

      # Forward totals start at the current hour so nothing already counted in past_72h repeats.
      def snow_summary(resort)
        @summaries                                ||= {}
        @summaries[resort.id || resort.object_id] ||= compute_snow_summary(resort)
      end

      def compute_snow_summary(resort)
        upcoming = resort.hourly_forecasts.map { |h| h.snowfall.to_f }
        {
          past_72h: resort.past_snowfall(hours: 72),
          next_24h: upcoming.take(24).sum.round(2),
          next_7d: upcoming.take(24 * 7).sum.round(2),
          next_16d: upcoming.sum.round(2)
        }
      end

      def raw_forecasts_for(resort)
        @raw_forecast_cache            ||= {}
        cache_key                        = resort.id || resort.object_id
        @raw_forecast_cache[cache_key] ||= resort.forecasts(aggregates: [])
      end
    end
  end
end
