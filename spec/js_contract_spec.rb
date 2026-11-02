# frozen_string_literal: true

require 'spec_helper'
require 'json'

# JS must not duplicate Ruby's snow level bounds: it reads `steps` from search-data.json.
RSpec.describe FollowTheSnow::Builder::Units, '#snow_level' do
  let(:js_files) { Dir[File.expand_path('../pages/**/*.js', __dir__)] }

  it 'finds the JS sources (guards against a silently empty glob)' do
    expect(js_files.map { |f| File.basename(f) }).to include('input.js', 'map.js', 'shared.js')
  end

  it 'keeps any SNOW_STEPS literal out of pages/**/*.js' do
    expect(js_files).not_to be_empty
    offenders = js_files.select { |f| File.read(f).match?(/SNOW_STEPS\s*=\s*\[/) }

    expect(offenders).to be_empty
  end

  it 'decodes the index from `steps`, failing when it is absent' do
    source = File.read(File.expand_path('../pages/lib/shared.js', __dir__))

    expect(source).to include('raw.steps')
    expect(source).to match(/throw new Error\([^)]*steps/)
  end

  it 'emits the Ruby constant as `steps` in search-data.json' do
    stub_weather_api
    SharedBuild.perform!
    index = JSON.parse(File.read(File.join(SharedBuild.build_dir, 'assets', 'search-data.json')))

    expect(index['steps']).to eq(FollowTheSnow::Builder::Units::SNOW_STEPS)
  end
end
