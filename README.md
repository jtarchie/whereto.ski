# Follow the snow

This is the app that builds the static site for Follow the Snow. It goes through
a list of ski resorts and locations to get the snow report (inches fallen).

## Usage

Building the site will take awhile. The OpenWeather API is used to get
information about current and upcoming snow conditions. They rate limit pretty
heavily, so a `sleep` is put in between every API call.

This will manually build the site.

```bash
bundle install
rake build # or rake fast
ruby -run -ehttpd docs/ -p8000
```

Then commit the changed pages, which will be deployed as a static site via
Github Pages and Cloudflare.

The page is build every morning from 6am MST, so that latest snow totals for the
day are available. This is using
[Github Actions](https://github.com/jtarchie/followthesnow/blob/main/.github/workflows/build.yml)
to do so.

### Test

Everything is tested because it should be.

```bash
bundle install
bundle exec rspec
```

## Sources

All the resorts are in CSV files in `resorts/` by country. They are scraped via
`rake scrape` from respective Wikipedia pages.

### Notes

Exploring getting information from website via scraping. Haven't done it because
it would cost money.

```javascript
document.body.querySelectorAll(
  "nav,header,footer,form,button,iframe,script,[role]",
).forEach((node) => node.remove());
document.body.textContent.trim().replace(/\s+/g, " ");
```

Using this content into an ChatGPT prompt:

> Please identify the current conditions reported at the resort. Include details
> of snow depth, if the resort is open, etc. Please put it in a JSON format,
> where the keys are simple to infer camel case keys.
