module Bikebuspdx
  class BusSiteGenerator < Jekyll::Generator
    def generate(site)
      dir = '_pages/buses'
      site.data['buses'].each do |bus|
        slug = bus['slug']
        site.pages << Jekyll::PageWithoutAFile.new(site, site.source, dir, slug + ".html").tap do |file|
          file.data.merge!(
            "layout" => 'page',
            'title' => "#{bus['name']} Bike Bus",
            'navigation_exclude' => true,
            'permalink' => "/#{slug}",
          )
          file.data['image'] = bus['image'] if bus['image']
          include_data = bus.dup
          include_data['map_image'] = bus['map_image'] ? bus['map_image'] : "/assets/images/routes/route-#{slug}.png"
          kvps = include_data.map { |k, v| "#{k}='#{v}' " }.join(' ')
          file.content = "{% include bus-minisite-content.html #{kvps} %}"
          file.output
        end
      end
    end
  end
end
