# frozen_string_literal: true

require 'spec_helper'

# Guard until the client reads `steps` from search-data.json.
RSpec.describe FollowTheSnow::Builder::Units, '#snow_level' do
  %w[input.js map.js].each do |file|
    it "keeps SNOW_STEPS in pages/#{file} equal to Units::SNOW_STEPS" do
      source  = File.read(File.expand_path("../pages/#{file}", __dir__))
      literal = source[/SNOW_STEPS\s*=\s*\[([^\]]*)\]/, 1]

      expect(literal).not_to be_nil, "no SNOW_STEPS literal found in pages/#{file}; update this guard"
      expect(literal.split(',').map { |n| Float(n.strip) }).to eq(FollowTheSnow::Builder::Units::SNOW_STEPS.map(&:to_f))
    end
  end
end
