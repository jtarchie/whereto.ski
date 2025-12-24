# frozen_string_literal: true

require 'babosa'
require 'sqlite3'
require 'unidecode'

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
      # Check if the name contains CJK characters (Chinese, Japanese, Korean)
      # CJK Unicode ranges: \u4e00-\u9fff (CJK Unified), \u3040-\u30ff (Hiragana/Katakana)
      has_cjk = name.match?(/[\u3040-\u30ff\u4e00-\u9fff]/)

      if has_cjk
        # For CJK names, use unidecode which provides good romanization
        # e.g., ニセコ → niseko, 白馬 → bai ma, 长白山 → chang bai shan
        name.to_ascii.to_slug.normalize.to_s
      else
        # For other scripts (Cyrillic, Greek, Turkish, etc.), use babosa
        # which provides better transliteration with language-specific rules
        slug           = name.to_slug
        transliterated = slug.transliterate(:cyrillic).transliterate(:greek).transliterate(:latin)
        transliterated.normalize.to_s
      end
    end

    def forecasts(aggregates: [
      Forecast::Daily
    ])
      @forecast ||= Forecast::OpenMeteo.new(
        resort: self
      )

      aggregates.reduce(@forecast) do |forecaster, aggregate|
        aggregate.new(
          forecasts: forecaster.forecasts
        )
      end.forecasts
    end
  end
end
