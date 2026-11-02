# frozen_string_literal: true

require 'json'
require 'rexml/document'

RSpec.describe 'icon/asset links' do # rubocop:disable RSpec/DescribeClass
  before(:all) do
    stub_weather_api
    SharedBuild.perform!
  end

  let(:dir) { SharedBuild.build_dir }
  # main.{css,js} are gitignored build outputs (rake assets), not checked here
  let(:built) { %w[/assets/main.css /assets/main.js] }

  def missing(urls)
    urls.reject { |u| built.include?(u) || File.exist?(File.join(dir, u)) }
  end

  it 'resolves every local href/src/icon content URL in index.html' do
    html = File.read(File.join(dir, 'index.html'))
    urls = html.scan(%r{\b(?:href|src)="(/[^"#?]*)"}).flatten +
           html.scan(%r{<meta[^>]+content="(/[^"]+)"}).flatten
    urls = urls.uniq.reject { |u| File.extname(u).empty? }

    expect(urls).to include('/assets/favicon/ms-icon-144x144.png')
    expect(missing(urls)).to be_empty
  end

  it 'resolves every icon in browserconfig.xml' do
    doc  = REXML::Document.new(File.read(File.join(dir, 'assets/favicon/browserconfig.xml')))
    urls = REXML::XPath.match(doc, '//tile/*[@src]').map { |e| e.attributes['src'] }
    expect(urls).not_to be_empty
    expect(missing(urls)).to be_empty
  end

  it 'resolves every icon in manifest.json' do
    json = JSON.parse(File.read(File.join(dir, 'assets/favicon/manifest.json')))
    urls = json['icons'].map { |i| i['src'] }
    expect(missing(urls)).to be_empty
  end
end
