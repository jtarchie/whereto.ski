# frozen_string_literal: true

require 'spec_helper'
require 'rack'
require 'nokogiri'

RSpec.describe('Ranked list', :js, type: :feature) do
  let(:build_dir) { @build_dir }

  before(:all) do
    stub_weather_api
    SharedBuild.perform!
    @build_dir      = SharedBuild.build_dir
    build_directory = @build_dir
    Capybara.app    = Rack::Builder.new do
      use Rack::Static,
          urls: ['/'],
          root: build_directory,
          index: 'index.html',
          cascade: true

      run lambda { |env|
        path      = env['PATH_INFO']
        file_path = File.join(build_directory, path)

        if File.file?(file_path)
          [200, { 'Content-Type' => Rack::Mime.mime_type(File.extname(path)) }, [File.read(file_path)]]
        elsif File.file?(File.join(build_directory, "#{path}.html"))
          content = File.read(File.join(build_directory, "#{path}.html"))
          [200, { 'Content-Type' => 'text/html' }, [content]]
        else
          [404, { 'Content-Type' => 'text/html' }, ['Not Found']]
        end
      }
    end
  end

  def ranks
    all('[data-ranked] tbody tr').map { |row| row.find('td.who a').text }
  end

  def column(key)
    all("[data-ranked] tbody td[data-s=\"#{key}\"] data", visible: :all).map { |d| d['value'].to_f }
  end

  it 'ranks every resort in the region by 7-day snow by default' do
    visit '/states/colorado'

    expect(find('th[data-s="7d"]')['aria-sort']).to eq('descending')
    expect(column('7d')).to eq(column('7d').sort.reverse)
  end

  it 'sorts by keyboard, reflects it in the URL, and restores on a second press' do
    visit '/states/colorado'
    default = ranks

    find('th[data-s="24h"] button').send_keys(:enter)
    expect(find('th[data-s="24h"]')['aria-sort']).to eq('descending')
    expect(find('th[data-s="7d"]')['aria-sort']).to eq('none')
    expect(column('24h')).to eq(column('24h').sort.reverse)
    expect(current_url).to end_with('?sort=24h')
    expect(first('[data-ranked] tbody td.rank').text).to eq('1')

    find('th[data-s="24h"] button').send_keys(:enter)
    expect(ranks).to eq(default)
    expect(current_url).not_to include('sort=')
  end

  it 'applies ?sort= on load, including a single day' do
    visit '/states/colorado'
    days = all('.days button', visible: :all).map { |b| b['data-sort'] }

    visit "/states/colorado?sort=#{days[5]}"
    values = all('[data-ranked] tbody tr', visible: :all).map do |row|
      bar = row.all('.strip i', visible: :all).find { |i| i[:style].start_with?('grid-column:6;') }
      bar&.[]('data-v').to_f
    end

    expect(find('th[data-s="day"]')['aria-sort']).to eq('descending')
    expect(values).to eq(values.sort.reverse)
  end

  describe 'region page' do
    def html(slug)
      File.read(File.join(build_dir, 'states', "#{slug}.html"))
    end

    it 'keeps the largest region under the 100 KB budget' do
      expect(html('bayern').bytesize).to be <= 100_000
    end

    it 'lists all resorts in the region' do
      rows = Nokogiri::HTML(html('bayern')).css('[data-ranked] tbody tr')
      expect(rows.length).to eq(114)
    end

    it 'says so when a region has no snow and points somewhere that does' do
      dry = Dir[File.join(build_dir, 'states', '*.html')].map { |f| File.read(f) }.find { |h| h.include?('No snow forecast in') }
      skip 'stubbed weather left no region dry' unless dry

      expect(dry).to include('the snowiest resorts worldwide')
    end
  end
end
