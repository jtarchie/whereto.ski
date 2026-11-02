# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'nokogiri'

# Tilt renders ERB without escape_html: every <%= %> needs a manual `h`. Hostile names must come out escaped everywhere.
RSpec.describe(FollowTheSnow::Builder::Site, '#build! escaping') do
  let(:raw_markup) { ['<img src=x', '<script>alert(1)', '<b onmouseover', '<i>Town</i>'] }
  let(:name) { %(<img src=x onerror=1> O'Brien "Peak") }
  let(:region)    { %(<b onmouseover=1>Reg</b> O'R "X") }
  let(:country)   { %(<script>alert(1)</script> Land "Q") }
  let(:build_dir) { Dir.mktmpdir }
  let(:pages_dir) { File.expand_path(File.join(__dir__, '..', 'pages')) }
  let(:hostile)   { build_resort(1, name) }
  # More than SMALL_COUNTRY_THRESHOLD resorts, so the state page is produced too.
  let(:resorts)   { [hostile] + (2..22).map { |i| build_resort(i, "Filler #{i}") } }
  let(:pages) do
    {
      resort: read('resorts', "#{hostile.slug}.html"),
      state: read('states', "#{region.to_url}.html"),
      country: read('countries', "#{country.to_url}.html"),
      index: read('index.html')
    }
  end

  def build_resort(id, resort_name)
    FollowTheSnow::Resort.new(
      id: id, lat: 39.0 + (id / 100.0), lon: -106.0, name: resort_name, region_code: 'XX-R', country_code: 'XX',
      country_name: country, region_name: region, url: 'https://example.com/?a=1&b="2"', min_elevation: 2000,
      max_elevation: 3000, locality: %(<i>Town</i> "L"), runs: {}, lifts: {}
    )
  end

  def read(*path)
    File.read(File.join(build_dir, *path))
  end

  before do
    stub_weather_api
    described_class.new(
      build_dir: build_dir, resorts: resorts, source_dir: pages_dir, logger_io: File.open(File::NULL, 'w')
    ).build!
  end

  after { FileUtils.rm_rf(build_dir) }

  it 'escapes the resort name in head, h1, and attributes' do
    html = pages[:resort]
    doc  = Nokogiri::HTML(html)

    expect(doc.title).to include(name)
    expect(doc.at_css('h1').text).to include(name)
    expect(doc.at_css('meta[name=description]')['content']).to include(name)
    expect(doc.at_css('meta[property="og:title"]')['content']).to include(name)
    expect(doc.at_css('meta[property="og:description"]')['content']).to include(name)
    expect(html).to include(CGI.escapeHTML(name))
  end

  it 'escapes hostile names on every generated page and keeps the layout intact' do
    pages.each do |key, html|
      doc = Nokogiri::HTML(html)

      raw_markup.each { |markup| expect(html).not_to include(markup), "#{key} page leaks #{markup}" }
      expect(doc.css('[onerror],[onmouseover]')).to be_empty, "#{key} page grew an event-handler attribute"
      expect(doc.at_css('html > head > title')).not_to be_nil, "#{key} page lost the layout"
      expect(doc.at_css('body h1')).not_to be_nil
      expect(html).not_to match(/^---\s*$/), "#{key} page leaked front matter"
    end
  end

  it 'escapes region and country in titles and breadcrumbs of the list pages' do
    expect(Nokogiri::HTML(pages[:state]).title).to include(region)
    expect(Nokogiri::HTML(pages[:country]).title).to include(country)
    expect(Nokogiri::HTML(pages[:resort]).css('nav a, nav li').map(&:text).join).to include(region).and include(country)
  end

  it 'keeps hostile names as plain data in the search index' do
    data = JSON.parse(read('assets', 'search-data.json'))

    expect(data['d'].map { |e| e['n'] }).to include(name, region, country)
    expect(data['cl']).to include(country)
  end
end
