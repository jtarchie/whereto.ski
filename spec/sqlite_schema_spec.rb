# frozen_string_literal: true

require 'spec_helper'

# Pins the contract Resort.from_sqlite relies on, so a scrape that changes the schema fails here, not mid-build.
RSpec.describe(FollowTheSnow::Resort, '.from_sqlite') do
  let(:path) { File.join(__dir__, '..', 'data', 'features.sqlite') }
  let(:db) { SQLite3::Database.new(path, readonly: true) }

  before do
    pointer = File.binread(path, 64).start_with?('version https://git-lfs')
    raise 'data/features.sqlite is a Git LFS pointer: run `git lfs pull`' if pointer
  end

  after { db.close }

  it 'has the resorts view columns the SELECT uses' do
    columns = db.table_info('resorts').map { |c| c['name'] }
    expect(columns).to include('id', 'name', 'lat', 'lon', 'url', 'min_elevation', 'max_elevation',
                               'country_code', 'region_code', 'region_name', 'country_name')
  end

  it 'has features.payload' do
    expect(db.table_info('features').map { |c| c['name'] }).to include('id', 'payload')
  end

  it 'has the JSON paths the query reads on some rows' do
    %w[
      $.properties.places[0].localized.en.locality
      $.properties.statistics.runs.byActivity.downhill.byDifficulty
      $.properties.statistics.lifts.byType
    ].each do |json_path|
      count = db.get_first_value('SELECT COUNT(*) FROM features WHERE payload->?1 IS NOT NULL', json_path)
      expect(count).to be > 0, "no rows have #{json_path}"
    end
  end

  it 'has >3000 usable resorts: a name and numeric coordinates' do
    sql = <<~SQL
      SELECT COUNT(*) FROM resorts
      WHERE name IS NOT NULL AND name != '' AND typeof(lat) IN ('real', 'integer') AND typeof(lon) IN ('real', 'integer')
    SQL

    expect(db.get_first_value(sql)).to be > 3000
  end
end
