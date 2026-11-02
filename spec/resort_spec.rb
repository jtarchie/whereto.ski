# frozen_string_literal: true

require 'spec_helper'

RSpec.describe('Resort') do
  it 'can load a sqlite file' do
    files = Dir[File.join(__dir__, '..', 'data', '*.sqlite')]
    expect(files.length).to be > 0

    files.each do |file|
      resorts = FollowTheSnow::Resort.from_sqlite(file)
      expect(resorts.length).to be > 0
    end
  end

  describe 'duplicate names' do
    let(:resorts) { FollowTheSnow::Resort.from_sqlite(File.join(__dir__, '..', 'data', 'features.sqlite')) }

    it 'keeps one copy of a resort listed twice' do
      expect(resorts.count { |r| r.name == 'Hovden' }).to eq(1)
      expect(resorts.count { |r| r.name == 'Snowshoe Mountain' }).to eq(1)
      expect(resorts.count { |r| r.slug.start_with?('saas-grund') }).to eq(1)
    end

    it 'keeps different resorts that share a name, each at its own URL' do
      crystal = resorts.select { |r| r.name == 'Crystal Mountain' }

      expect(crystal.to_h { |r| [r.region_name, r.slug] })
        .to eq('Washington' => 'crystal-mountain', 'Michigan' => 'crystal-mountain-michigan')
    end

    it 'gives every resort with a usable name a unique URL' do
      slugs = resorts.map(&:slug).reject(&:empty?)

      expect(slugs.length).to eq(slugs.uniq.length)
    end
  end

  describe 'terrain data' do
    let(:steamboat) do
      FollowTheSnow::Resort.from_sqlite(File.join(__dir__, '..', 'data', 'features.sqlite'))
                           .find { |r| r.name == 'Steamboat Ski Resort' }
    end

    it 'loads locality, runs, lifts and vertical from OpenSkiMap' do
      expect(steamboat.locality).to eq('Steamboat Springs')
      expect(steamboat.runs.sum { |_, r| r[:count] }).to eq(199)
      expect(steamboat.runs['advanced']).to eq(count: 80, km: 50.0)
      expect(steamboat.lifts.sum { |_, l| l[:count] }).to eq(20)
      expect(steamboat.vertical).to eq(1103)
    end
  end

  describe '#slug' do
    it 'generates URL-friendly slugs from resort names' do
      resort = FollowTheSnow::Resort.new(name: 'Vail Resort')
      expect(resort.slug).to eq('vail-resort')
    end

    it 'handles names with special characters' do
      resort = FollowTheSnow::Resort.new(name: 'St. Moritz - Corviglia')
      expect(resort.slug).to eq('st-moritz-corviglia')
    end

    it 'transliterates Cyrillic characters (Russian)' do
      resort = FollowTheSnow::Resort.new(name: 'Красная Поляна')
      expect(resort.slug).to eq('krasnaia-poliana')
    end

    it 'transliterates Greek characters' do
      resort = FollowTheSnow::Resort.new(name: 'Καλαβρυτα')
      expect(resort.slug).to eq('kalabruta')
    end

    it 'transliterates German umlauts' do
      resort = FollowTheSnow::Resort.new(name: 'Gölcük')
      expect(resort.slug).to eq('golcuk')
    end

    it 'transliterates Turkish characters' do
      resort = FollowTheSnow::Resort.new(name: 'Palandöken')
      expect(resort.slug).to eq('palandoken')
    end

    it 'transliterates Japanese characters (Katakana)' do
      resort = FollowTheSnow::Resort.new(name: 'ニセコ')
      expect(resort.slug).to eq('niseko')
    end

    it 'transliterates Japanese characters (Kanji)' do
      resort = FollowTheSnow::Resort.new(name: '白馬')
      expect(resort.slug).to eq('bai-ma')
    end

    it 'transliterates Chinese characters (Simplified)' do
      resort = FollowTheSnow::Resort.new(name: '长白山')
      expect(resort.slug).to eq('chang-bai-shan')
    end

    it 'transliterates Chinese characters (Traditional)' do
      resort = FollowTheSnow::Resort.new(name: '長白山')
      expect(resort.slug).to eq('chang-bai-shan')
    end

    it 'transliterates Bulgarian characters' do
      resort = FollowTheSnow::Resort.new(name: 'Банско')
      expect(resort.slug).to eq('bansko')
    end

    it 'handles mixed Latin and non-Latin characters' do
      resort = FollowTheSnow::Resort.new(name: 'Горнолыжный курорт Rosa Khutor')
      expect(resort.slug).to eq('gornolyzhnyi-kurort-rosa-khutor')
    end

    it 'removes extra spaces and hyphens' do
      resort = FollowTheSnow::Resort.new(name: 'Mt.  Hood  - Meadows')
      expect(resort.slug).to eq('mt-hood-meadows')
    end

    it 'handles names with parentheses' do
      resort = FollowTheSnow::Resort.new(name: 'Ski Resort (Main Area)')
      expect(resort.slug).to eq('ski-resort-main-area')
    end

    it 'handles Norwegian characters' do
      resort = FollowTheSnow::Resort.new(name: 'Trysil')
      expect(resort.slug).to eq('trysil')
    end
  end

  describe 'from_sqlite hardening' do
    def feature(name:, coords:)
      props        = { status: 'operating', activities: ['downhill'], location: { 'iso3166_1Alpha2' => 'us', 'iso3166_2' => 'us-co' } }
      props[:name] = name unless name.nil?
      { type: 'Feature', properties: props, geometry: { type: 'Point', coordinates: coords } }.to_json
    end

    let(:path) { File.join(Dir.mktmpdir, 'test.sqlite') }

    before do
      db = SQLite3::Database.new(path)
      db.execute_batch(<<~SQL)
        CREATE TABLE countries(id TEXT, alpha2 TEXT, alpha3 TEXT, name TEXT);
        CREATE TABLE subdivisions(country TEXT, code TEXT, name TEXT);
        CREATE TABLE features (id INTEGER PRIMARY KEY, payload BLOB) STRICT;
        INSERT INTO countries VALUES ('1', 'US', 'USA', 'United States');
        INSERT INTO subdivisions VALUES ('US', 'US-CO', 'Colorado');
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
        FROM features
        JOIN subdivisions, countries
        ON UPPER(subdivisions.code) = region_code AND UPPER(subdivisions.country) = country_code AND UPPER(countries.alpha2) = country_code;
      SQL
      [
        feature(name: 'Good Peak', coords: [-106.0, 39.0]),
        feature(name: nil, coords: [-105.0, 38.0]),
        feature(name: '', coords: [-104.0, 37.0]),
        feature(name: 'No Coords', coords: [])
      ].each_with_index { |json, i| db.execute('INSERT INTO features VALUES (?, ?)', [i + 1, SQLite3::Blob.new(json)]) }
      db.close
    end

    it 'skips rows with NULL/empty name or missing coordinates' do
      expect(FollowTheSnow::Resort.from_sqlite(path).map(&:name)).to eq(['Good Peak'])
    end

    it 'closes the database handle' do
      handles = []
      allow(SQLite3::Database).to(receive(:new).and_wrap_original { |m, *a| m.call(*a).tap { |d| handles << d } })

      FollowTheSnow::Resort.from_sqlite(path)

      expect(handles).not_to be_empty
      expect(handles).to all(be_closed)
    end
  end
end
