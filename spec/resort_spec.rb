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
end
