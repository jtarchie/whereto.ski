# frozen_string_literal: true

require 'json'
require 'sqlite3'
require 'stringex'
require 'active_support/core_ext/module/delegation'

module FollowTheSnow
  Resort = Struct.new(
    :id,
    :lat,
    :lon,
    :name,
    :region_code,
    :country_code,
    :country_name,
    :region_name,
    :url,
    :min_elevation,
    :max_elevation,
    :locality,
    :runs,
    :lifts,
    :slug_suffix,
    keyword_init: true
  ) do
    def self.from_sqlite(filename)
      db      = SQLite3::Database.new filename
      rows    = db.prepare(<<~SQL).execute
        SELECT
          resorts.*,
          payload->>'$.properties.places[0].localized.en.locality' AS locality,
          payload->'$.properties.statistics.runs.byActivity.downhill.byDifficulty' AS runs,
          payload->'$.properties.statistics.lifts.byType' AS lifts
        FROM resorts
        JOIN features ON features.id = resorts.id
      SQL
      results = []
      rows.each_hash do |payload|
        payload['runs']  = parse_stats(payload['runs'])
        payload['lifts'] = parse_stats(payload['lifts'])
        results.push Resort.new(payload)
      end
      rows.close

      disambiguate(dedupe(results))
    end

    # OpenSkiMap sometimes lists one resort twice, split across a region border or spelled two ways ("Эльбрус"/"Elbrus"):
    # same URL slug within ~10 km.
    def self.dedupe(resorts)
      resorts.group_by(&:slug).values.flat_map do |same|
        same.each_with_object([]) do |resort, kept|
          kept << resort unless kept.any? { |k| (k.lat - resort.lat).abs < 0.1 && (k.lon - resort.lon).abs < 0.1 }
        end
      end
    end

    # Different resorts can share a URL (two Crystal Mountains); the one with the most runs keeps it, the rest get
    # their region appended.
    def self.disambiguate(resorts)
      resorts.group_by(&:slug).except('').each_value do |same|
        by_size                                            = same.sort_by { |resort| -(resort.runs || {}).sum { |_, stat| stat[:count] } }
        by_size.drop(1).each { |resort| resort.slug_suffix = resort.region_name.to_url }
      end
      resorts
    end

    # OpenSkiMap stats: { "advanced" => { count:, km: } }, empty when unmapped.
    def self.parse_stats(json)
      return {} if json.nil?

      JSON.parse(json).transform_values do |stat|
        { count: stat['count'].to_i, km: stat['lengthInKm'].to_f.round(1) }
      end
    end

    # OpenSkiMap elevations are meters.
    def vertical
      return nil unless min_elevation && max_elevation

      (max_elevation - min_elevation).round
    end

    def slug
      # Stringex provides excellent transliteration for all character sets:
      # - CJK (Chinese, Japanese, Korean): ニセコ → niseko, 白馬 → bai-ma, 长白山 → chang-bai-shan
      # - Cyrillic (Russian, Bulgarian, etc.): Красная Поляна → krasnaia-poliana
      # - Greek: Καλαβρυτα → kalabruta
      # - Turkish, German, etc.: Gölcük → golcuk, Palandöken → palandoken
      # - Special characters: rock & roll → rock-and-roll, $12 → 12-dollars
      [name.to_url, slug_suffix].compact.join('-')
    end

    def forecasts(aggregates: [
      Forecast::Daily
    ])
      aggregates.reduce(forecast_client) do |forecaster, aggregate|
        aggregate.new(
          forecasts: forecaster.forecasts
        )
      end.forecasts
    end

    def hourly_forecasts
      forecast_client.hourly_forecasts
    end

    def current_conditions
      forecast_client.current_conditions
    end

    delegate :base_forecasts, :base_hourly_forecasts, :past_snowfall, :snow_depth, :timezone,
             to: :forecast_client

    private

    def forecast_client
      @forecast_client ||= Forecast::OpenMeteo.new(
        resort: self
      )
    end
  end
end
