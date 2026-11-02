# frozen_string_literal: true

require 'active_support'
require 'active_support/inflector'
require 'fileutils'
require 'front_matter_parser'
require 'ougai'
require 'parallel'
require 'ruby-limiter'
require 'stringex'
require 'tilt'
require 'tilt/erb'
require_relative 'builder/context'

module FollowTheSnow
  module Builder
    # builds the entire site
    class Site
      def initialize(build_dir:, resorts:, source_dir:, logger_io: $stderr, limiter: nil)
        @build_dir    = build_dir
        @context      = Context.new(resorts: resorts, source_dir: source_dir)
        @logger       = Ougai::Logger.new(logger_io)
        @logger.level = Ougai::Logger::DEBUG
        @source_dir   = source_dir
        @num_threads  = 5
        @limiter      = limiter
        @cache        = {}
        @cache_lock   = Mutex.new
      end

      def resorts
        @context.resorts
      end

      def build!
        assert_unique_slugs!
        FileUtils.mkdir_p(@build_dir)
        FileUtils.copy_entry(File.join(@source_dir, 'public'), @build_dir)

        generate_redirects

        layout_html = erb(File.join(@source_dir, '_layout.html.erb'))

        # Collect all template files
        all_templates = Dir[File.join(@source_dir, '**', '*.html.erb')].reject do |filename|
          File.basename(filename) =~ /^_/
        end

        # Group templates by type for ordered processing
        resort_templates  = all_templates.select { |f| f.include?('[resort]') }
        state_templates   = all_templates.select { |f| f.include?('[state]') }
        country_templates = all_templates.select { |f| f.include?('[country]') }
        other_templates   = all_templates - resort_templates - state_templates - country_templates

        # Process in order: resorts (with rate limiting), then states, then countries, then others
        # This ensures API rate limiting is in place before any calls happen
        [resort_templates, state_templates, country_templates, other_templates].each do |templates|
          templates.each do |filename|
            build_filename = filename.gsub(@source_dir, @build_dir).gsub('.html.erb', '.html')
            FileUtils.mkdir_p(File.dirname(build_filename))

            case filename
            when /\[resort\]/
              # Open-Meteo allows 600 calls/min; each resort is 2 (base + summit), halved for safety
              limiter  = @limiter || Limiter::RateQueue.new(25, interval: 10, balanced: true)
              # specs build every resort against stubbed weather; only the default limiter is skipped there
              throttle = @limiter || !defined?(RSpec)

              # Filter out resorts with names that don't generate valid slugs
              valid_resorts = resorts.reject { |r| r.name.to_url.empty? }

              # Pass 1, fetch everything first: pages read nearby resorts' forecasts, which must not bypass the limiter.
              fetch_all(valid_resorts, limiter, throttle)

              Parallel.each(valid_resorts, in_threads: @num_threads * 10) do |resort|
                resort_filename = build_filename.gsub('[resort]', resort.slug)
                write_file(
                  layout_html,
                  filename,
                  resort_filename,
                  {
                    resort: resort
                  }
                )
              end
            when /\[state\]/
              Parallel.each(buildable_states, in_threads: @num_threads) do |state|
                state_filename = build_filename.gsub('[state]', state.to_url)
                write_file(
                  layout_html,
                  filename,
                  state_filename,
                  {
                    resorts: resorts_by_state(state),
                    state: state
                  }
                )
              end
            when /\[country\]/
              Parallel.each(countries, in_threads: @num_threads) do |country|
                country_filename = build_filename.gsub('[country]', country.to_url)
                write_file(
                  layout_html,
                  filename,
                  country_filename,
                  {
                    country: country,
                    states: resorts_by_country(country)
                  }
                )
              end
            else
              write_file(layout_html, filename, build_filename)
            end
          end
        end

        # After resort pages: the index carries 7-day snow, so forecasts must already be fetched under the limiter.
        generate_search_index
        generate_sitemap
      end

      private

      def fetch_all(resorts, limiter, throttle)
        Parallel.each(resorts, in_threads: @num_threads * 10) do |resort|
          limiter.shift if throttle
          resort.timezone
        end
      end

      # Two resorts on one slug would silently overwrite each other's page; Resort.disambiguate should make this impossible.
      def assert_unique_slugs!
        dupes = resorts.map(&:slug).reject(&:empty?).tally.select { |_, count| count > 1 }.keys
        raise "duplicate resort slug(s): #{dupes.join(', ')}" unless dupes.empty?
      end

      def generate_search_index
        require 'json'

        # Build lookup tables for repeated strings
        country_list   = countries
        # Create numeric lookup for countries (most repeated)
        country_lookup = country_list.each_with_index.to_h

        # Build search data with optimizations:
        # - Single-char type codes: c=country, s=state, r=resort
        # - Country references use numeric index
        # - Shorter key names: n=name, u=url, c=country, s=state
        search_data = {
          cl: country_list, # country lookup
          d: [] # data entries
        }

        # Add countries (just name and URL, type implied by structure)
        country_list.each do |country|
          search_data[:d] << {
            t: 'c',
            n: country,
            u: "/countries/#{country.to_url}"
          }
        end

        # Add states (skip for small countries)
        buildable_states.each do |state|
          sample_resort = resorts_by_state(state).first
          search_data[:d] << {
            t: 's',
            n: state,
            c: country_lookup[sample_resort.country_name], # numeric index
            u: "/states/#{state.to_url}"
          }
        end

        # Add resorts (filter out those with empty slug names)
        resorts.each do |resort|
          next if resort.slug.empty?

          snow = @context.snow_summary(resort)[:next_7d].round(1)
          search_data[:d] << {
            t: 'r',
            n: resort.name,
            c: country_lookup[resort.country_name], # numeric index
            s: resort.region_name,
            u: "/resorts/#{resort.slug}",
            l: [resort.lat.round(3), resort.lon.round(3)],
            w: (snow if snow.positive?)
          }.compact
        end

        search_file = File.join(@build_dir, 'assets', 'search-data.json')
        File.write(search_file, JSON.generate(search_data))
        @logger.info('generated search index', { file: search_file, entries: search_data[:d].length })
      end

      # Cloudflare Pages serves /foo.html at /foo, which is the canonical form every page declares.
      def generate_sitemap
        paths = Dir[File.join(@build_dir, '**', '*.html')].map { |f| f.delete_prefix(@build_dir).delete_suffix('.html') }
        urls  = (paths - ['/404']).map { |path| path == '/index' ? '/' : path }.sort.map do |path|
          "<url><loc>https://whereto.ski#{path}</loc></url>"
        end
        File.write(File.join(@build_dir, 'sitemap.xml'), <<~XML)
          <?xml version="1.0" encoding="UTF-8"?>
          <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
          #{urls.join("\n")}
          </urlset>
        XML
      end

      # Snow Now pages were retired; send their old URLs to the parent scope. Small countries never had region pages.
      def generate_redirects
        lines  = ['/snow-now / 301']
        lines += countries.map { |c| "/countries/#{c.to_url}-snow-now /countries/#{c.to_url} 301" }
        lines += buildable_states.map { |s| "/states/#{s.to_url}-snow-now /states/#{s.to_url} 301" }
        File.write(File.join(@build_dir, '_redirects'), "#{lines.join("\n")}\n")
      end

      def resorts_by_state(state)
        @resorts_by_state ||= resorts.group_by(&:region_name)
        @resorts_by_state.fetch(state)
      end

      def states
        @states ||= resorts.map(&:region_name).uniq.sort
      end

      # States get pages and search entries unless their country is small (its resorts are listed directly).
      def buildable_states
        @buildable_states ||= states.reject { |state| @context.small_country?(resorts_by_state(state).first.country_name) }
      end

      def resorts_by_country(country)
        @resorts_by_country ||= resorts.group_by(&:country_name)
        @resorts_by_country.fetch(country)
      end

      def countries
        @countries ||= resorts.map(&:country_name).uniq.sort
      end

      def write_file(layout, source_filename, build_filename, metadata = {})
        template       = erb(source_filename)
        @frontmatter ||= FrontMatterParser::Parser.new(:html)
        parsed_file    = @frontmatter.call(template.render(@context, metadata))

        front_matter = parsed_file.front_matter
        contents     = parsed_file.content
        variables    = front_matter
                       .merge(metadata)
                       .merge({
                                content: contents
                              })

        @logger.info('writing file', { source: source_filename, build_filename: build_filename })
        FileUtils.mkdir_p(File.dirname(build_filename))
        File.write(
          build_filename,
          # Herb-formatted templates are mostly indentation; pages have no <pre>/<textarea>, so leading space is noise.
          layout.render(@context, variables).gsub(/\n\s+/, "\n")
        )
      end

      def erb(filename)
        @cache_lock.synchronize { @cache[filename] ||= Tilt::ERBTemplate.new(filename, trim: true) }
      end
    end
  end
end
