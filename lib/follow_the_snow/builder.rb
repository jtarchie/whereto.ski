# frozen_string_literal: true

require 'active_support'
require 'active_support/inflector'
require 'fileutils'
require 'front_matter_parser'
require 'ougai'
require 'parallel'
require 'ruby-limiter'
require 'tilt'
require 'tilt/erb'
require_relative 'builder/context'

module FollowTheSnow
  module Builder
    # builds the entire site
    class Site
      def initialize(build_dir:, resorts:, source_dir:, logger_io: $stderr)
        @build_dir    = build_dir
        @context      = Context.new(resorts: resorts)
        @logger       = Ougai::Logger.new(logger_io)
        @logger.level = Ougai::Logger::DEBUG
        @source_dir   = source_dir
        @num_threads  = 5
      end

      def resorts
        @context.resorts
      end

      def build!
        FileUtils.mkdir_p(@build_dir)
        FileUtils.copy_entry(File.join(@source_dir, 'public'), @build_dir)

        # Generate search index
        generate_search_index

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
              # rate limit from open meteo (600 / minute) halved for safety
              limiter = Limiter::RateQueue.new(50, interval: 10, balanced: true)

              # Filter out resorts with names that don't parameterize properly (e.g., Cyrillic, Greek)
              valid_resorts = resorts.reject { |r| r.name.parameterize.empty? }

              Parallel.each(valid_resorts, in_threads: @num_threads * 10) do |resort|
                limiter.shift unless defined?(RSpec)

                resort_filename = build_filename.gsub('[resort]', resort.name.parameterize)
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
              # Skip state pages for countries with few resorts
              states_to_build = states.reject do |state|
                # Find which country this state belongs to
                sample_resort = resorts_by_state(state).first
                @context.small_country?(sample_resort.country_name)
              end

              Parallel.each(states_to_build, in_threads: @num_threads) do |state|
                state_filename = build_filename.gsub('[state]', state.parameterize)
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
                country_filename = build_filename.gsub('[country]', country.parameterize)
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
      end

      private

      def generate_search_index
        require 'json'

        # Build lookup tables for repeated strings
        country_list = countries
        states.reject do |state|
          sample_resort = resorts_by_state(state).first
          @context.small_country?(sample_resort.country_name)
        end

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
            u: "/countries/#{country.parameterize}"
          }
        end

        # Add states (skip for small countries)
        states.each do |state|
          sample_resort = resorts_by_state(state).first
          next if @context.small_country?(sample_resort.country_name)

          search_data[:d] << {
            t: 's',
            n: state,
            c: country_lookup[sample_resort.country_name], # numeric index
            u: "/states/#{state.parameterize}"
          }
        end

        # Add resorts (filter out those with empty parameterized names)
        resorts.each do |resort|
          next if resort.name.parameterize.empty?

          search_data[:d] << {
            t: 'r',
            n: resort.name,
            c: country_lookup[resort.country_name], # numeric index
            s: resort.region_name,
            u: "/resorts/#{resort.name.parameterize}"
          }
        end

        search_file = File.join(@build_dir, 'assets', 'search-data.json')
        File.write(search_file, JSON.generate(search_data))
        @logger.info('generated search index', { file: search_file, entries: search_data[:d].length })
      end

      def resorts_by_state(state)
        @resorts_by_state ||= resorts.group_by(&:region_name)
        @resorts_by_state.fetch(state)
      end

      def states
        @states ||= resorts.map(&:region_name).uniq.sort
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
          layout.render(@context, variables)
        )
      end

      def erb(filename)
        @cache ||= {}
        @cache.fetch(filename, Tilt::ERBTemplate.new(filename, trim: true))
      end
    end
  end
end
