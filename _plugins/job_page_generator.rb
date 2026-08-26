require 'jekyll'

module Bikebuspdx
  # Generates a detail page at /jobs/<slug> for each entry in _data/jobs.yml,
  # so job postings live in one data file rather than one page file each.
  class JobPageGenerator < Jekyll::Generator
    def generate(site)
      jobs = site.data['jobs'] || []
      dir = '_pages/jobs'
      jobs.each do |job|
        next if job['unlist']
        slug = job.fetch('slug')
        page = Jekyll::PageWithoutAFile.new(site, site.source, dir, slug + '.html')
        page.data.merge!(
          'layout' => 'page',
          'title' => job.fetch('title'),
          'description' => summary(job['description']),
          'navigation_exclude' => true,
          'permalink' => "/jobs/#{slug}",
        )
        page.data['image'] = job['image'] if job['image']
        page.content = "{% include job-listing.html slug='#{slug}' %}"
        site.pages << page
      end
    end

    # Collapse the YAML block scalar's newlines into single spaces. Without
    # this, head.html's `strip_newlines` joins the lines with no separator
    # and the meta description reads 'EastPortland'.
    def summary(text)
      return nil unless text
      text.gsub(/\s+/, ' ').strip
    end
  end
end
