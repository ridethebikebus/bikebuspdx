module Bikebuspdx
  class BusSiteGenerator < Jekyll::Generator
    def generate(site)
      dir = '_pages/buses'
      site.data['buses'].each do |bus|
        site.pages << Jekyll::PageWithoutAFile.new(site, site.source, dir, bus['slug'] + ".html").tap do |file|
          file.data.merge!(
            "layout" => 'page',
            'title' => "#{bus['name']} Bike Bus",
            'navigation_exclude' => true,
            'permalink' => "/#{bus['slug']}"
          )
          kvps = bus.map { |k, v| "#{k}='#{v}' " }.join(' ')
          file.content = "{% include bus-minisite-content.html #{kvps} %}"
          file.output
        end
      end
    end
  end
end
