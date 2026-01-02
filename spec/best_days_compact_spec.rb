# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'nokogiri'

RSpec.describe('Best Days to Ski - Compact View') do
  let(:build_dir) { @build_dir }

  before(:all) do
    stub_weather_api

    @build_dir = Dir.mktmpdir
    pages_dir  = File.expand_path(File.join(__dir__, '..', 'pages'))
    sqlite     = File.expand_path(File.join(__dir__, '..', 'data', 'features.sqlite'))
    resorts    = FollowTheSnow::Resort.from_sqlite(sqlite)

    builder = FollowTheSnow::Builder::Site.new(
      build_dir: @build_dir,
      resorts: resorts,
      source_dir: pages_dir,
      logger_io: File.open(File::NULL, 'w')
    )

    builder.build!
  end

  after(:all) do
    FileUtils.rm_rf(@build_dir) if @build_dir && File.exist?(@build_dir)
  end

  describe 'resort page best days section' do
    it 'has a compact best days section' do
      resort_files = Dir[File.join(build_dir, 'resorts', '*.html')].first(5)

      resort_files.each do |file|
        html = File.read(file)
        doc  = Nokogiri::HTML(html)

        # Should have best days section with compact styling
        best_days_section = doc.at_xpath("//*[contains(text(), 'Best Days to Ski')]")
        expect(best_days_section).not_to be_nil, "Resort page should have 'Best Days to Ski' section"
      end
    end

    it 'uses horizontal scrollable layout for ski day cards' do
      resort_files = Dir[File.join(build_dir, 'resorts', '*.html')].first(5)

      resort_files.each do |file|
        html = File.read(file)
        doc  = Nokogiri::HTML(html)

        # Look for flex container with overflow-x-auto
        flex_container = doc.at_xpath("//*[contains(@class, 'overflow-x-auto') and contains(@class, 'flex')]")
        expect(flex_container).not_to be_nil, "Should have horizontal scrollable flex container"
      end
    end

    it 'has compact ski day cards with shrink-0 class' do
      resort_files = Dir[File.join(build_dir, 'resorts', '*.html')].first(5)

      resort_files.each do |file|
        html = File.read(file)
        doc  = Nokogiri::HTML(html)

        # Find ski-day-card elements
        cards = doc.xpath("//*[contains(@class, 'ski-day-card')]")
        next if cards.empty?

        cards.each do |card|
          expect(card['class']).to include('shrink-0'), "Cards should have shrink-0 class"
          expect(card['class']).to include('min-w-16'), "Cards should have min-w-16 class"
        end
      end
    end

    it 'shows recommendation badge instead of large box' do
      resort_files = Dir[File.join(build_dir, 'resorts', '*.html')].first(10)

      resort_files.each do |file|
        html = File.read(file)
        doc  = Nokogiri::HTML(html)

        # Should NOT have the old recommendation box
        expect(html).not_to include('💡 Recommendation:')

        # Should have badge for recommendations (if score is high)
        badge = doc.at_xpath("//*[contains(@class, 'badge') and contains(text(), 'recommended')]")

        # Badge is optional (only shows for high scores), so we just check structure is valid
        next unless badge

        expect(badge['class']).to include('badge-success')
      end
    end

    it 'does not have separate description paragraph' do
      resort_files = Dir[File.join(build_dir, 'resorts', '*.html')].first(5)

      resort_files.each do |file|
        html = File.read(file)

        # Should NOT have the old description
        expect(html).not_to include('Based on snow, wind, and temperature conditions')
      end
    end
  end

  describe 'state page best days section' do
    it 'has a compact best days section' do
      state_files = Dir[File.join(build_dir, 'states', '*.html')].reject { |f| f.include?('snow-now') }.first(5)

      state_files.each do |file|
        html = File.read(file)
        doc  = Nokogiri::HTML(html)

        # Should have best days section
        best_days_section = doc.at_xpath("//*[contains(text(), 'Best Days in')]")
        expect(best_days_section).not_to be_nil, "State page should have 'Best Days in' section"
      end
    end

    it 'uses horizontal scrollable layout for ski day cards on state pages' do
      state_files = Dir[File.join(build_dir, 'states', '*.html')].reject { |f| f.include?('snow-now') }.first(5)

      state_files.each do |file|
        html = File.read(file)
        doc  = Nokogiri::HTML(html)

        # Look for flex container with overflow-x-auto
        flex_container = doc.at_xpath("//*[contains(@class, 'overflow-x-auto') and contains(@class, 'flex')]")
        expect(flex_container).not_to be_nil, "Should have horizontal scrollable flex container"
      end
    end

    it 'shows resort count inline instead of in separate paragraph' do
      state_files = Dir[File.join(build_dir, 'states', '*.html')].reject { |f| f.include?('snow-now') }.first(5)

      state_files.each do |file|
        html = File.read(file)
        doc  = Nokogiri::HTML(html)

        # Should have inline resort count
        resort_count = doc.at_xpath("//*[contains(@class, 'text-base-content/60') and contains(text(), 'resorts')]")
        expect(resort_count).not_to be_nil, "Should have inline resort count"

        # Should NOT have the old paragraph style
        expect(html).not_to include('Aggregated across')
      end
    end

    it 'does not have large recommendation box' do
      state_files = Dir[File.join(build_dir, 'states', '*.html')].reject { |f| f.include?('snow-now') }.first(10)

      state_files.each do |file|
        html = File.read(file)

        # Should NOT have the old recommendation box
        expect(html).not_to include('💡 Best day:')
      end
    end

    it 'shows best day as inline badge' do
      state_files = Dir[File.join(build_dir, 'states', '*.html')].reject { |f| f.include?('snow-now') }.first(10)

      state_files.each do |file|
        html = File.read(file)
        doc  = Nokogiri::HTML(html)

        # Badge is optional (only shows for high scores)
        badge = doc.at_xpath("//*[contains(@class, 'badge') and contains(text(), 'best')]")
        next unless badge

        expect(badge['class']).to include('badge-success')
      end
    end
  end
end
