# GitHub Copilot Instructions for Follow the Snow

This file provides guidance to GitHub Copilot for generating code and
suggestions that align with the conventions and best practices of the Follow the
Snow repository.

## Repository Overview

Follow the Snow is a Ruby-based static site generator that builds a website
displaying snow reports for ski resorts worldwide. The application:

- Fetches weather data from the Open-Meteo API
- Stores ski resort information in SQLite databases
- Generates static HTML pages using ERB templates
- Deploys to Cloudflare Pages via GitHub Actions

**Key Technologies:**

- Ruby 3.4+
- SQLite for data storage
- ERB for templating
- RSpec for testing
- RuboCop for linting
- GitHub Actions for CI/CD

## Project Structure

```
.
├── lib/
│   └── follow_the_snow/         # Core application code
│       ├── builder/             # Site builder components
│       ├── forecasts/           # Weather forecast models
│       ├── forecast.rb          # Main forecast logic
│       ├── openskimap.rb        # OpenSkiMap data integration
│       └── resort.rb            # Resort model and data handling
├── pages/                       # ERB templates and site content
│   └── public/                  # Static assets (CSS, JS)
├── data/                        # SQLite databases with resort data
├── spec/                        # RSpec tests
├── docs/                        # Generated static site (git-ignored)
└── Rakefile                     # Build tasks and automation
```

## Ruby Coding Conventions

### Style Guide

Follow the RuboCop configuration defined in `.rubocop.yml`:

1. **Target Ruby Version**: 3.4
2. **Frozen String Literals**: Always include `# frozen_string_literal: true` at
   the top of Ruby files
3. **Hash Syntax**: Use classic hash rockets (`=>`) instead of shorthand syntax
   (project standard, deviates from modern Ruby conventions)
4. **Line Length**: No strict limit, but be reasonable
5. **Documentation**: Class and module documentation is not required
6. **Equal Sign Alignment**: Align equal signs in consecutive assignments for
   readability

### Code Organization

- Use descriptive class and module names without nesting concerns
- Keep methods focused and single-purpose
- Prefer composition over inheritance
- Use Ruby's enumerable methods (`map`, `select`, `each`) idiomatically

### Example Code Pattern

```ruby
# frozen_string_literal: true

module FollowTheSnow
  class ExampleClass
    def initialize(param:)
      @param = param
    end

    def process
      results = fetch_data
      results.map { |item| transform_item(item) }
    end

    private

    def fetch_data
      # Implementation
    end

    def transform_item(item)
      # Implementation
    end
  end
end
```

## Testing Conventions

### RSpec Guidelines

1. **File Structure**: Test files mirror the structure of `lib/` in `spec/`
2. **Naming**: Spec files end with `_spec.rb`
3. **Setup**: Use `spec_helper.rb` for shared configuration
4. **WebMock**: Use WebMock to stub HTTP requests in tests
5. **Helpers**: Common test helpers (like `stub_geo_lookup`) are defined in
   `spec_helper.rb`

### Test Writing Best Practices

```ruby
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe(FollowTheSnow::ExampleClass) do
  describe '#process' do
    it 'transforms data correctly' do
      instance = described_class.new(param: 'value')
      result = instance.process
      
      expect(result).to be_an(Array)
      expect(result.first).to have_key(:transformed_data)
    end
  end

  context 'when parameter is invalid' do
    it 'raises an error' do
      expect do
        described_class.new(param: nil)
      end.to raise_error(ArgumentError)
    end
  end
end
```

## API Integration Patterns

### Weather Data Fetching

When working with weather APIs:

1. Always implement rate limiting to respect API quotas
2. Use the `ruby-limiter` gem for rate limiting
3. Cache results when appropriate
4. Handle API errors gracefully with retries and fallbacks
5. Use structured logging with the `ougai` gem

### Example API Client Pattern

```ruby
# frozen_string_literal: true

require 'http'
require 'ruby-limiter'

module FollowTheSnow
  class APIClient
    def initialize(api_key:, rate_limiter:)
      @api_key = api_key
      @rate_limiter = rate_limiter
      @logger = create_logger
    end

    def fetch_data(params)
      @rate_limiter.wait do
        response = HTTP.get(api_url, params: params.merge(api_key: @api_key))
        
        if response.status.success?
          JSON.parse(response.body.to_s)
        else
          @logger.error('API request failed', status: response.status, body: response.body)
          nil
        end
      end
    rescue StandardError => e
      @logger.error('Exception during API request', error: e.message)
      nil
    end

    private

    def api_url
      'https://api.example.com/data'
    end

    def create_logger
      # Logger setup
    end
  end
end
```

## Database Patterns

### SQLite Usage

The project uses SQLite for storing resort and geographic data:

1. **Read-Only Access**: Most operations read from pre-built databases
2. **Schema Design**: Keep tables normalized but optimize for read performance
3. **Connection Management**: Close connections after use
4. **Data Loading**: Use bulk inserts for efficiency when building databases

### Example Database Interaction

```ruby
# frozen_string_literal: true

require 'sqlite3'

module FollowTheSnow
  class Resort
    def self.from_sqlite(db_path)
      db = SQLite3::Database.new(db_path)
      db.results_as_hash = true
      
      results = db.execute('SELECT * FROM resorts')
      resorts = results.map { |row| new(row) }
      
      db.close
      resorts
    end

    def initialize(attributes)
      @attributes = attributes
    end
  end
end
```

## Build and Deployment

### Rake Tasks

The project uses Rake for automation:

- `rake build` - Build the complete site with live data
- `rake fast` - Build with mock data for development
- `rake test` - Run RSpec tests
- `rake fmt` - Format code with RuboCop and other tools
- `rake scrape` - Update resort data from OpenSkiMap

### Development Workflow

1. Make code changes in `lib/` or `pages/`
2. Run `rake fmt` to format code
3. Run `rake test` to verify tests pass
4. Use `rake fast` for quick site previews
5. Use `rake build` for production builds

### GitHub Actions

The repository uses GitHub Actions for:

- Daily automated site builds (10:00 UTC / 5 AM EST)
- Deployment to Cloudflare Pages
- Linting and testing on pull requests

When modifying workflows, ensure:

- Ruby version matches `.ruby-version`
- Secrets are properly referenced
- Cache strategies are used for dependencies

**Note**: The OPENWEATHER_API_KEY environment variable in workflows is legacy
and currently unused. The project uses the Open-Meteo API which does not require
an API key for basic usage.

## ERB Template Guidelines

### Template Structure

1. **Layouts**: Use consistent layout patterns across pages
2. **Partials**: Extract reusable components into partials
3. **Data Binding**: Pass data explicitly through locals
4. **Formatting**: Use `erb_lint` for consistent formatting

### Example ERB Pattern

```erb
<%# Page title and meta information %>
<!DOCTYPE html>
<html lang="en">
<head>
  <title><%= page_title %></title>
  <meta name="description" content="<%= page_description %>">
</head>
<body>
  <%# Main content %>
  <main>
    <% resorts.each do |resort| %>
      <article class="resort">
        <h2><%= resort.name %></h2>
        <p><%= resort.location %></p>
        <%= render_snowfall_data(resort) %>
      </article>
    <% end %>
  </main>
</body>
</html>
```

## Performance Considerations

1. **Parallel Processing**: Use the `parallel` gem for concurrent operations
2. **Rate Limiting**: Always respect API rate limits with `ruby-limiter`
3. **Caching**: Cache expensive computations and API responses
4. **Lazy Loading**: Load data only when needed
5. **Database Queries**: Optimize SQLite queries with proper indexes

## Security Best Practices

1. **API Keys**: Never commit API keys; use environment variables
2. **Input Validation**: Validate and sanitize all external data
3. **SQL Injection**: Use parameterized queries for SQLite
4. **XSS Protection**: Escape user-provided content in ERB templates
5. **Dependencies**: Keep gems updated for security patches

## Error Handling

### Logging Strategy

Use the `ougai` gem for structured logging:

```ruby
require 'ougai'

logger = Ougai::Logger.new($stdout)
logger.info('Processing resort', resort: resort.name, id: resort.id)
logger.warn('Rate limit approaching', remaining: remaining_requests)
logger.error('Failed to fetch data', error: e.message, resort: resort.name)
```

### Graceful Degradation

- Handle API failures by using cached or default data
- Log errors for debugging but don't crash the build
- Provide meaningful error messages for troubleshooting

## Common Patterns in This Codebase

### Builder Pattern

The site builder uses a modular builder pattern:

```ruby
builder = FollowTheSnow::Builder::Site.new(
  build_dir: 'docs',
  resorts: resorts,
  source_dir: 'pages'
)
builder.build!
```

### Data Pipeline Pattern

Data flows through a pipeline:

1. Fetch from external sources (APIs, OpenSkiMap)
2. Store in SQLite database
3. Load and transform for site generation
4. Render to static HTML
5. Deploy to hosting

## Contributing Guidelines

### Updating Copilot Instructions

As the project evolves, update this file to reflect:

1. **New Patterns**: Document new architectural patterns or conventions
2. **API Changes**: Update API integration examples
3. **Tool Updates**: Reflect changes in build tools or testing frameworks
4. **Best Practices**: Add lessons learned from code reviews or issues

### Review Process

When updating these instructions:

1. Discuss significant changes in pull requests
2. Get consensus from maintainers
3. Test that Copilot suggestions improve with the updates
4. Keep examples up-to-date with actual code in the repository

## Helpful Commands

```bash
# Development
bundle install              # Install dependencies
bundle exec rspec           # Run tests
bundle exec rubocop -A      # Auto-fix linting issues
rake fast                   # Quick build for development
ruby -run -ehttpd docs/ -p8000  # Preview generated site

# Production
rake build                  # Full production build
rake scrape                 # Update resort data

# Formatting
rake fmt                    # Format all code
```

## Resources

- [Ruby Style Guide](https://rubystyle.guide/)
- [RSpec Best Practices](https://rspec.info/documentation/)
- [RuboCop Documentation](https://docs.rubocop.org/)
- [Open-Meteo API Documentation](https://open-meteo.com/en/docs)
- [GitHub Copilot Documentation](https://docs.github.com/en/copilot)

## Questions or Issues?

If you encounter scenarios not covered in these instructions:

1. Refer to existing code patterns in `lib/` for consistency
2. Check the README.md for project-specific context
3. Follow Ruby community best practices
4. Open an issue or discussion for clarification

---

**Last Updated**: 2025-11-06 **Maintainers**: Please update this file when
introducing new patterns or conventions.
