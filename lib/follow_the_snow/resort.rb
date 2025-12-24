# frozen_string_literal: true

require 'sqlite3'
require 'stringex'

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
    keyword_init: true
  ) do
    def self.from_sqlite(filename)
      db      = SQLite3::Database.new filename
      rows    = db.prepare('SELECT * FROM resorts').execute
      results = []
      rows.each_hash do |payload|
        results.push Resort.new(payload)
      end
      results.uniq(&:name)
      rows.close

      results
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

    private

    def forecast_client
      @forecast_client ||= Forecast::OpenMeteo.new(
        resort: self
      )
    end
  end
end
