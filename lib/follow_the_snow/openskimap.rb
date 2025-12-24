# frozen_string_literal: true

require 'active_support/core_ext/object'
require 'down'
require 'fast_ostruct'
require 'http'
require 'json'
require 'ruby-limiter'
require 'sqlite3'

module FollowTheSnow
  class OpenSkiMapBuilder
    def initialize(data_dir:)
      @data_dir     = data_dir
      @logger       = Ougai::Logger.new($stderr)
      @logger.level = Ougai::Logger::DEBUG
    end

    def build!
      filename = File.join(@data_dir, 'features.sqlite')
      geojson  = File.join(@data_dir, 'ski_areas.geojson')
      Down.download('https://tiles.openskimap.org/geojson/ski_areas.geojson', destination: geojson) unless File.exist?(geojson)

      payload = JSON.parse(File.read(geojson))

      FileUtils.rm_f(filename)

      # import countries
      Dir[File.join(@data_dir, 'countries', '*.csv')].each do |csv|
        table_name = File.basename(csv, '.csv')
        system("sqlite3 #{filename} -cmd '.import -csv #{csv} #{table_name}' 'SELECT COUNT(*) FROM #{table_name};'")
      end

      db = SQLite3::Database.new filename
      db.execute <<-SQL
        CREATE TABLE IF NOT EXISTS features (
          id INTEGER PRIMARY KEY,
          payload BLOB
        ) STRICT;
      SQL

      db.execute <<-SQL
        CREATE VIEW resorts AS SELECT
          features.id,
          payload->>'$.properties.name' AS name,
          payload->>'$.geometry.coordinates[0]' AS lon,
          payload->>'$.geometry.coordinates[1]' AS lat,
          payload->>'$.properties.websites[0]' AS url,
          payload->>'$.properties.statistics.minElevation' AS min_elevation,
          payload->>'$.properties.statistics.maxElevation' AS max_elevation,
          UPPER(payload->>'$.properties.location.iso3166_1Alpha2') AS country_code,
          UPPER(payload->>'$.properties.location.iso3166_2') AS region_code,
          subdivisions.name AS region_name,
          countries.name AS country_name
        FROM
          features
        JOIN
          subdivisions, countries
        ON
          UPPER(subdivisions.code) = region_code AND
          UPPER(subdivisions.country) = country_code AND
          UPPER(countries.alpha2) = country_code
        WHERE
          payload->>'$.geometry.type' = 'Point' AND
          payload->>'$.properties.name' IS NOT NULL AND
          payload->>'$.properties.status' = 'operating' AND
          payload->>'$.properties.activities' LIKE '%downhill%' AND
          country_code IN (
            'AD',
            'AL',
            'AM',
            'AR',
            'AT',
            'AU',
            'BA',
            'BE',
            'BG',
            'BY',
            'CA',
            'CH',
            'CL',
            'CN',
            'CY',
            'CZ',
            'DE',
            'DK',
            'EE',
            'ES',
            'FI',
            'FO',
            'FR',
            'GB',
            'GE',
            'GG',
            'GI',
            'GR',
            'HR',
            'HU',
            'IE',
            'IM',
            'IN',
            'IR',
            'IS',
            'IT',
            'JE',
            'JP',
            'KG',
            'KR',
            'KZ',
            'LB',
            'LI',
            'LT',
            'LU',
            'LV',
            'MC',
            'MD',
            'ME',
            'MK',
            'MT',
            'NL',
            'NO',
            'NZ',
            'PK',
            'PL',
            'PT',
            'RO',
            'RS',
            'RU',
            'SE',
            'SI',
            'SJ',
            'SK',
            'SM',
            'TR',
            'UA',
            'US',
            'VA'
          );
      SQL

      payload.fetch('features').each_with_index do |feature, index|
        coordinates = feature.dig('geometry', 'coordinates')
        if coordinates && coordinates[0].is_a?(Array)
          coordinates.flatten!
          feature['geometry']['coordinates'] = coordinates[0..1]
          feature['geometry']['type']        = 'Point'
        end

        region_code  = feature.dig('properties', 'location', 'iso3166_2')
        country_code = feature.dig('properties', 'location', 'iso3166_1Alpha2')

        if [country_code, region_code].any?(&:blank?)
          lat = feature.dig('geometry', 'coordinates', 1)
          lon = feature.dig('geometry', 'coordinates', 0)

          address = find_address(lat, lon)

          key = address.keys.grep(/^ISO3166-2/).max_by { |k| k[/\d+$/].to_i }
          @logger.info(
            'address',
            index: index,
            out_of: payload.fetch('features').size,
            address: address,
            key: key,
            lat: lat,
            lon: lon
          )

          feature['properties']['location'] = {
            'iso3166_2' => address[key]&.upcase,
            'iso3166_1Alpha2' => address['country_code']&.upcase
          }
        end

        db.execute('INSERT INTO features (payload) VALUES (jsonb(?))', [feature.to_json])
      rescue StandardError => e
        @logger.error(e)
      end

      db.close
    end

    private

    def find_address(lat, lon)
      @limiter ||= Limiter::RateQueue.new(60, interval: 60, balanced: true)
      @limiter.shift unless defined?(RSpec)
      response   = JSON.parse(HTTP.follow.headers('Accept-Language' => 'en-US,en;q=0.5', 'User-Agent' => 'FollowTheSnow/1.0').timeout(20).get(%(https://nominatim.openstreetmap.org/reverse?lat=#{lat.to_f}&lon=#{lon.to_f}&format=jsonv2)).to_s)
      response['address']
    end
  end
end
