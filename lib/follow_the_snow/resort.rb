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
      results = []
      rows    = db.prepare(<<~SQL).execute
        SELECT
          resorts.*,
          payload->>'$.properties.places[0].localized.en.locality' AS locality,
          payload->'$.properties.statistics.runs.byActivity.downhill.byDifficulty' AS runs,
          payload->'$.properties.statistics.lifts.byType' AS lifts
        FROM resorts
        JOIN features ON features.id = resorts.id
        WHERE resorts.name IS NOT NULL AND resorts.name != ''
          AND resorts.lat IS NOT NULL AND resorts.lon IS NOT NULL
      SQL
      rows.each_hash do |payload|
        payload['runs']  = parse_stats(payload['runs'])
        payload['lifts'] = parse_stats(payload['lifts'])
        results.push Resort.new(payload)
      end
      rows.close

      disambiguate(dedupe(results))
    ensure
      db&.close
    end

    # OpenSkiMap sometimes lists one resort twice, split across a region border or spelled two ways ("Эльбрус"/"Elbrus"):
    # same URL slug within ~10 km. The lowest id survives (the order rows already arrive in), so the result doesn't
    # depend on query order. Survivors keep their input order.
    def self.dedupe(resorts)
      kept = resorts.group_by(&:slug).values.flat_map do |same|
        same.sort_by(&:id).each_with_object([]) do |resort, winners|
          winners << resort unless winners.any? { |k| (k.lat - resort.lat).abs < 0.1 && (k.lon - resort.lon).abs < 0.1 }
        end
      end.to_set(&:object_id)

      resorts.select { |resort| kept.include?(resort.object_id) }
    end

    # Different resorts can share a URL (two Crystal Mountains); the one with the most runs keeps it, the rest get
    # their region appended. Same-name resorts in one region still collide, so the id is the last-resort suffix.
    def self.disambiguate(resorts)
      named = resorts.reject { |resort| resort.slug.empty? }
      suffix_losers(named) { |resort| resort.region_name.to_url }
      suffix_losers(named) { |resort| [resort.slug_suffix, resort.id].compact.join('-') }
      resorts
    end

    # Within each group sharing a slug, everyone but the biggest (most runs, then lowest id) gets a new suffix.
    def self.suffix_losers(resorts)
      resorts.group_by(&:slug).each_value do |same|
        same.sort_by { |resort| [-run_count(resort), resort.id] }.drop(1).each { |resort| resort.slug_suffix = yield(resort) }
      end
    end

    def self.run_count(resort)
      (resort.runs || {}).sum { |_, stat| stat[:count] }
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
      # Memoized per name (to_url is slow, slug is read many times per page); the suffix is applied fresh each call.
      @slug_base = [name, name.to_url] unless @slug_base&.first == name
      [@slug_base.last, slug_suffix].compact.join('-')
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

    FORECAST_CLIENT_LOCK = Mutex.new

    private

    # Resort pages render on many threads; without the lock two could each build (and fetch with) their own client.
    def forecast_client
      @forecast_client || FORECAST_CLIENT_LOCK.synchronize do
        @forecast_client ||= Forecast::OpenMeteo.new(
          resort: self
        )
      end
    end
  end
end
