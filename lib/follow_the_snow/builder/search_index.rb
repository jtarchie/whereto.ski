# frozen_string_literal: true

require 'stringex'
require_relative 'units'

module FollowTheSnow
  module Builder
    # Compact-key index for pages/input.js and map.js: t c/s/r, n, u, c = index into cl, s, l = [lat, lon], w = 7d snow.
    class SearchIndex
      # buildable gates state entries (small countries have no state pages).
      def initialize(resorts:, countries:, states:, buildable:, snow_7d:)
        @resorts   = resorts
        @countries = countries
        @states    = states
        @buildable = buildable
        @snow_7d   = snow_7d
      end

      def to_h
        lookup = @countries.each_with_index.to_h
        {
          cl: @countries,
          d: country_entries + state_entries(lookup) + resort_entries(lookup),
          steps: Units::SNOW_STEPS
        }
      end

      private

      def country_entries
        @countries.map { |country| { t: 'c', n: country, u: "/countries/#{country.to_url}" } }
      end

      def state_entries(lookup)
        by_state = @resorts.group_by(&:region_name)
        @states.select(&@buildable).map do |state|
          { t: 's', n: state, c: lookup[by_state.fetch(state).first.country_name], u: "/states/#{state.to_url}" }
        end
      end

      # Resorts with empty slugs have no page, so no entry.
      def resort_entries(lookup)
        @resorts.reject { |resort| resort.slug.empty? }.map do |resort|
          snow = @snow_7d.call(resort).round(1)
          {
            t: 'r',
            n: resort.name,
            c: lookup[resort.country_name],
            s: resort.region_name,
            u: "/resorts/#{resort.slug}",
            l: [resort.lat.round(3), resort.lon.round(3)],
            w: (snow if snow.positive?)
          }.compact
        end
      end
    end
  end
end
