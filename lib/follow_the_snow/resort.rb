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
      results.uniq(&:name)
      rows.close

      results
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
      name.to_url
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
