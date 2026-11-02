# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe(FollowTheSnow::Builder::Site) do
  let(:source_dir) { Dir.mktmpdir }
  let(:build_dir)  { Dir.mktmpdir }
  let(:resorts) do
    Array.new(4) do |i|
      FollowTheSnow::Resort.new(
        id: i + 1, name: "Peak #{i + 1}", lat: 40.0 + i, lon: -105.0, region_name: 'Colorado', country_name: 'USA',
        runs: {}
      )
    end
  end

  before do
    FileUtils.mkdir_p(File.join(source_dir, 'public'))
    FileUtils.mkdir_p(File.join(source_dir, 'resorts'))
    File.write(File.join(source_dir, '_layout.html.erb'), '<%= content %>')
    File.write(File.join(source_dir, 'resorts', '[resort].html.erb'), '<p><%= resort.name %></p>')
  end

  after do
    FileUtils.rm_rf([source_dir, build_dir])
  end

  def site(limiter: nil)
    described_class.new(
      build_dir: build_dir, resorts: resorts, source_dir: source_dir, limiter: limiter,
      logger_io: File.open(File::NULL, 'w')
    ).tap { |s| allow(s).to receive(:generate_search_index) }
  end

  it 'refuses to build when two resorts would write the same page' do
    twin = FollowTheSnow::Resort.new(id: 99, name: 'Peak 1', lat: 1.0, lon: 1.0, region_name: 'Colorado', country_name: 'USA')

    builder = described_class.new(
      build_dir: build_dir, resorts: resorts + [twin], source_dir: source_dir, logger_io: File.open(File::NULL, 'w')
    )

    expect { builder.build! }.to raise_error(/duplicate resort slug.*peak-1/i)
    expect(Dir[File.join(build_dir, '**', '*.html')]).to be_empty
  end

  it 'fetches every resort through the limiter before writing any resort page' do
    events  = Queue.new
    limiter = Class.new do
      def initialize(events) = @events = events
      def shift = @events << [:shift]
    end.new(events)
    wrote = Queue.new

    resorts.each do |resort|
      allow(resort).to receive(:timezone) do
        # Under the old fetch-and-render-per-thread loop this resort fetched only after another had already rendered;
        # the bounded pop gives that ordering a chance to occur (it never does when all fetches come first).
        wrote.pop(timeout: 0.2) if resort.id == resorts.last.id
        events << [:fetch, resort.id]
        'UTC'
      end
    end

    builder = site(limiter: limiter)
    allow(builder).to receive(:write_file).and_wrap_original do |original, *args|
      if args[1].end_with?('[resort].html.erb')
        events << [:write, args[2]]
        wrote << true
      end
      original.call(*args)
    end
    builder.build!

    log = Array.new(events.size) { events.pop }
    expect(log.count { |e| e.first == :shift }).to eq(4)
    expect(log.count { |e| e.first == :fetch }).to eq(4)
    expect(log.count { |e| e.first == :write }).to eq(4)
    expect(log.rindex { |e| e.first == :fetch }).to be < log.index { |e| e.first == :write }
  end

  it 'parses each template once, however many pages render it' do
    template = File.join(source_dir, 'page.html.erb')
    File.write(template, 'hi')
    allow(Tilt::ERBTemplate).to receive(:new).and_call_original

    builder   = site
    templates = Array.new(20) { Thread.new { builder.send(:erb, template) } }.map(&:value)

    expect(templates.uniq.length).to eq(1)
    expect(Tilt::ERBTemplate).to have_received(:new).once
  end

  it 'refuses to give a state page to a region name shared by two countries' do
    resorts = [
      FollowTheSnow::Resort.new(id: 1, name: 'Alpha', lat: 50.0, lon: 5.0, region_name: 'Limburg', country_name: 'Belgium'),
      FollowTheSnow::Resort.new(id: 2, name: 'Beta', lat: 51.0, lon: 5.5, region_name: 'Limburg', country_name: 'Netherlands')
    ]
    builder = described_class.new(build_dir: build_dir, resorts: resorts, source_dir: source_dir, logger_io: File.open(File::NULL, 'w'))
    allow(builder.instance_variable_get(:@context)).to receive(:small_country?).and_return(false)

    expect { builder.send(:buildable_states) }.to raise_error(/Limburg.*spans countries: Belgium, Netherlands/)
  end
end
