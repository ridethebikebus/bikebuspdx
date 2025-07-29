require 'net/http'

module Bikebuspdx
  class BusSiteGenerator < Jekyll::Generator

    def generate(site)
      rows = make_request
      merged = merge_data(site.data.fetch('buses'), rows)
      site.data['buses'] = merged
      dir = '_pages/buses'
      site.data['buses'].each do |bus|
        slug = bus.fetch('slug')
        name = bus.fetch('name')
        site.pages << Jekyll::PageWithoutAFile.new(site, site.source, dir, slug + ".html").tap do |file|
          file.data.merge!(
            "layout" => 'page',
            'title' => "#{name} Bike Bus",
            'navigation_exclude' => true,
            'permalink' => "/#{slug}",
          )
          file.data['image'] = bus['image'] if bus['image']
          include_data = bus.dup
          include_data['email'] = bus['email'] || "#{slug}@bikebuspdx.org"
          include_data['map_image'] = bus['map_image'] || "/assets/images/routes/route-#{slug}.png"
          include_data['map_alt'] = bus['map_alt'] || "#{name} Bike Bus Route Map"
          kvps = include_data.map { |k, v| "#{k}='#{v}' " }.join(' ')
          file.content = "{% include bus-minisite-content.html #{kvps} %}"
          file.output
        end
      end
    end

    def merge_data(buses, rows)
      keyed_by_name = buses.each_with_object({}) { |b, h| h[b.fetch('name')] = b }
      rows.each do |row|
        name = row.fetch('name')
        h = (keyed_by_name[name] ||= {})
        h.merge!(row)
        h['slug'] = name.downcase.gsub(' ', '-')
        set_socials(h)
        h.keys.each { |k| h.delete(k) if h[k] == "" }
      end
      keyed_by_name.values
    end

    def set_socials(h)
      if (s = h.fetch('bluesky', "")).length > 0
        s = s.delete_prefix("https://bsky.app/profile/")
        s = s.delete_prefix('@')
        h['bluesky'] = s
      end
      if (s = h.fetch('instagram', '')).length > 0
        s = s.delete_prefix("https://www.instagram.com/")
        s = s.delete_prefix('@')
        h['instagram'] = s
      end
    end

    def make_request
      url = "https://api.webhookdb.com/v1/db/run_sql" +
            "?query_base64=" + URI.encode_uri_component(Base64.strict_encode64(self.select_sql)) +
            "&org_identifier=" + URI.encode_uri_component(self.webhookdb_org)
      uri = URI(url)
      req = Net::HTTP::Get.new(uri)
      req['Accept'] = 'application/json'
      req['Whdb-Sha256-Conn'] = self.webhookdb_hash
      req['User-Agent'] = 'bikebuspdx.org website generator'

      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
        http.request(req)
      end

      if res.code.to_i >= 400
        raise "Request to WebhookDB failed: #{res.code}: #{res.body}"
      end

      body = JSON.parse(res.body)
      headers = body.fetch('headers')
      rows = body.fetch('rows').map { |r| headers.each_with_index.map { |h, i| [h, r[i]] }.to_h }
      rows
    end

    def webhookdb_table = @webhookdb_table ||= ENV.fetch('WEBHOOKDB_TABLE', 'jotform_webhook_v1_ce87')
    def webhookdb_org = @webhookdb_org ||= ENV.fetch('WEBHOOKDB_ORG', 'bikebuspdx')
    def webhookdb_conn_url = @webhookdb_conn_url ||= ENV.fetch('WEBHOOKDB_CONNECTION_URL')
    def webhookdb_hash = @webhookdb_hash ||= Digest::SHA256.hexdigest(self.webhookdb_conn_url)
    def form_update_secret = @form_update_secret ||= ENV.fetch('FORM_UPDATE_SECRET')

    def select_sql
      @select_sql ||= <<~SQL
        SELECT
            DISTINCT ON (questions->>'school', questions->>'schooltext')
            CASE
                WHEN questions->>'school' != '' THEN questions->>'school'
                ELSE questions->>'schooltext' END
                AS name,
            questions->'maintext' as content,
            questions->'websitelabel' as link_text,
            questions->'websitelink' as link_href,
            questions->'headerimage'->>0 as image,
            questions->'image1'->>0 as map_image,
            questions->'image2'->>0 as map_image2,
            questions->'routemaplink' as map_href,
            questions->>'bluesky' as bluesky,
            questions->>'instagram' as instagram
        FROM #{webhookdb_table}
        WHERE questions->>'password' = '#{form_update_secret}'
        ORDER BY questions->>'school', questions->>'schooltext', submit_date DESC
      SQL
    end
  end
end
