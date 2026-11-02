# frozen_string_literal: true

require 'spec_helper'

RSpec.describe FollowTheSnow::Builder::SearchIndex do
  def resort(id, name, country, region)
    FollowTheSnow::Resort.new(id: id, name: name, lat: 40.12345 + id, lon: -105.6789, region_name: region, country_name: country, runs: {})
  end

  let(:threshold) { FollowTheSnow::Builder::Context::SMALL_COUNTRY_THRESHOLD }
  let(:big)       { Array.new(threshold + 1) { |i| resort(i + 1, "Big #{i}", 'Bigland', i.even? ? 'North' : 'South') } }
  let(:small)     { Array.new(threshold - 1) { |i| resort(100 + i, "Small #{i}", 'Aland', 'Only') } }
  let(:nameless)  { resort(999, '!!!', 'Aland', 'Only') }
  let(:resorts)   { big + small + [nameless] }
  let(:context)   { FollowTheSnow::Builder::Context.new(resorts: resorts) }
  let(:snow)      { ->(r) { r.id == 1 ? 3.14159 : 0 } }
  let(:index) do
    described_class.new(
      resorts: resorts,
      countries: context.countries,
      states: resorts.map(&:region_name).uniq.sort,
      buildable: ->(state) { !context.small_country?(resorts.find { |r| r.region_name == state }.country_name) },
      snow_7d: snow
    ).to_h
  end
  let(:entries) { index[:d].group_by { |e| e[:t] } }

  it 'has exactly the documented top-level keys' do
    expect(index.keys).to eq(%i[cl d steps])
    expect(index[:steps]).to eq(FollowTheSnow::Builder::Units::SNOW_STEPS)
  end

  it 'has the documented keys per entry type' do
    expect(entries.keys).to contain_exactly('c', 's', 'r')
    expect(entries['c'].map(&:keys).uniq).to eq([%i[t n u]])
    expect(entries['s'].map(&:keys).uniq).to eq([%i[t n c u]])
    expect(entries['r'].map(&:keys)).to all(satisfy { |k| (%i[t n c s u l] - k).empty? && (k - %i[t n c s u l w]).empty? })
    expect(entries['r'].find { |e| e[:u] == '/resorts/big-0' }).to include(w: 3.1, l: [41.123, -105.679])
    expect(entries['r'].count { |e| e.key?(:w) }).to eq(1)
  end

  it 'points every c at a country in cl' do
    with_country = index[:d].select { |e| e.key?(:c) }

    expect(with_country).not_to be_empty
    expect(with_country.map { |e| index[:cl][e[:c]] }).to eq(
      with_country.map { |e| e[:t] == 's' ? 'Bigland' : (big + small).find { |r| "/resorts/#{r.slug}" == e[:u] }.country_name }
    )
  end

  it 'has state entries only for large countries' do
    expect(entries['s'].map { |e| e[:n] }).to eq(%w[North South])
    expect(entries['s'].map { |e| index[:cl][e[:c]] }.uniq).to eq(['Bigland'])
  end

  it 'skips resorts without a slug' do
    expect(nameless.slug).to be_empty
    expect(entries['r'].map { |e| e[:u] }).not_to include('/resorts/')
    expect(entries['r'].length).to eq(resorts.length - 1)
  end
end
