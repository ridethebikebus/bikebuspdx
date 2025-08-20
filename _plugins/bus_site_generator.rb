require 'fileutils'
require 'jekyll'
require 'net/http'
require 'tempfile'
require 'unicode_normalize/normalize'
require_relative '../bikebuspdx/webp'

module Bikebuspdx
  class BusSiteGenerator < Jekyll::Generator
    class << self
      # We only want to fetch data and images on the first build.
      # Otherwise it takes way too long when iterating on the site.
      attr_accessor :fetched_rows
      attr_accessor :generated_images
    end

    IMAGE_KEYS = ['image', 'map_image', 'map_image2']

    def generate(site)
      rows = fetch_webhookdb_rows
      merged = merge_data(site.data.fetch('buses'), rows)
      delete_unlisted(merged)
      clean_buses(merged)
      rehost_images(site, merged)
      merged.sort_by! { |b| b.fetch('slug')}
      site.data['buses'] = merged
      # merged.each { |h| puts h if h['name'] == 'Winterhaven' }
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
          include_data['map_alt'] = bus['map_alt'] || "#{name} Bike Bus Route Map"
          kvps = include_data.map { |k, v| "#{k}='#{v}' " }.join(' ')
          file.content = "{% include bus-minisite-content.html #{kvps} %}"
          file.output
        end
      end
    end

    def delete_unlisted(data)
      data.delete_if { |h| (h['unlist'] || '').length > 0 }
    end

    def clean_buses(data)
      data.each do |bus|
        bus.to_a.each { |(k, v)| bus.delete(k) if !v || v == "" }
        bus['slug'] ||= to_slug(bus.fetch('name'))
      end
    end

    def to_slug(s)
      slug = s.downcase.gsub(' ', '-')
      # :nfkd decomposes the characters (e.g. à → a + ̀)
      slug = slug.unicode_normalize(:nfkd)
      # /\p{Mn}/ matches the diacritic marks, which are then removed
      slug = slug.gsub(/\p{Mn}/, '')
      slug
    end

    def merge_data(buses, rows)
      keyed_by_name = buses.each_with_object({}) { |b, h| h[b.fetch('name')] = b }
      rows.each do |row|
        name = row.fetch('name')
        h = (keyed_by_name[name] ||= {})
        h.merge!(row)
        set_socials(h)
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

    def rehost_images(site, data)
      return if self.class.generated_images
      data.each do |h|
        IMAGE_KEYS.each do |k|
          link = h[k]
          needs_rehost = link && link =~ /^https?:\/\//
          next unless needs_rehost
          asset_rel_path = "autoimages/#{h.fetch('slug')}/#{k}.webp"
          out_path = "assets/#{asset_rel_path}"
          is_new = !File.exist?(out_path)
          next if !is_new && self.use_local_images
          res = get_url(link)
          Jekyll.logger.info :bikebusgen, "rehosting #{link} (status: #{res.code}, size: #{res.body.size}) to #{out_path}"
          FileUtils.mkdir_p(File.dirname(out_path))
          Tempfile.create(File.basename(link), binmode: true) do |f|
            f.write(res.body)
            f.flush
            Bikebuspdx::Webp.compress!(f.path, out_path)
          end
          # If the output file did not exist when the build started, we need to explicitly add it as a static file,
          # so it's copied to the _site build folder. Otherwise, the file is placed in the (source) assets directory,
          # but not copied over to the build folder, so doesn't get included in production.
          site.static_files << Jekyll::StaticFile.new(site, site.source, 'assets', asset_rel_path) if is_new
          h[k] = "/#{out_path}"
        end
      end
      self.class.generated_images = true
    end

    def fetch_webhookdb_rows
      if webhookdb_conn_url.nil?
        Jekyll.logger.warn :bikebusgen, "WEBHOOKDB_CONNECTION_URL not configured, falling back to static content only."
        return []
      end
      return self.class.fetched_rows if self.class.fetched_rows
      url = "https://api.webhookdb.com/v1/db/run_sql" +
            "?query_base64=" + URI.encode_uri_component(Base64.strict_encode64(self.select_sql)) +
            "&org_identifier=" + URI.encode_uri_component(self.webhookdb_org)
      res = get_url(
        url,
        headers: {'Accept' => 'application/json', 'Whdb-Sha256-Conn' => self.webhookdb_hash},
      )
      body = JSON.parse(res.body)
      headers = body.fetch('headers')
      rows = body.fetch('rows').map do |r|
        row = headers.each_with_index.map { |h, i| [h, r[i]] }.to_h
        if (name = row['name']) == 'Cesar Chavez'
          row['name'] = 'César Chávez'
        elsif name[0].downcase == name[0]
          row['name'] = name[0].upcase + name[1..]
        end
        row
      end
      self.class.fetched_rows = rows
      rows
    end

    def get_url(url, headers: {}, limit: 10)
      raise ArgumentError, "HTTP redirect too deep: #{url}" if limit == 0

      uri = URI(url)
      req = Net::HTTP::Get.new(uri)
      headers.each do |k, v|
        req[k] = v
      end
      req['User-Agent'] = 'bikebuspdx.org website generator'

      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
        http.request(req)
      end
      return get_url(res['location'], headers:, limit: limit - 1) if
        res.is_a?(Net::HTTPRedirection)

      raise "Request to #{url} failed: #{res.code}: #{res.body}" if res.code.to_i >= 400
      res
    end

    def webhookdb_table = @webhookdb_table ||= ENV.fetch('WEBHOOKDB_TABLE', 'jotform_webhook_v1_ce87')
    def webhookdb_org = @webhookdb_org ||= ENV.fetch('WEBHOOKDB_ORG', 'bikebuspdx')
    def webhookdb_conn_url = @webhookdb_conn_url ||= ENV.fetch('WEBHOOKDB_CONNECTION_URL', nil)
    def webhookdb_hash = @webhookdb_hash ||= Digest::SHA256.hexdigest(self.webhookdb_conn_url)
    def form_update_secret = @form_update_secret ||= ENV.fetch('FORM_UPDATE_SECRET', nil)
    # True to use local copies of images. Should only be used locally during development
    # to avoid pulling images every time the server starts.
    # Do not use in production, since it'd potentially cause stale images to be used.
    def use_local_images = @use_local_images ||= ENV.fetch('USE_LOCAL_IMAGES', nil)

    def select_sql
      @select_sql ||= <<~SQL
        SELECT
            DISTINCT ON (lower(questions->>'school'), lower(questions->>'schooltext'))
            CASE
                WHEN questions->>'school' != '' THEN questions->>'school'
                ELSE questions->>'schooltext' END
                AS name,
            questions->>'maintext' as content,
            questions->>'websitelabel' as link_text,
            questions->>'websitelink' as link_href,
            questions->'headerimage'->>0 as image,
            questions->'image1'->>0 as map_image,
            questions->'image2'->>0 as map_image2,
            questions->>'routemaplink' as map_href,
            questions->>'unlist' as unlist,
            questions->>'email' as email,
            questions->>'bluesky' as bluesky,
            questions->>'instagram' as instagram
        FROM #{webhookdb_table}
        WHERE questions->>'password' = '#{form_update_secret}'
        ORDER BY lower(questions->>'school'), lower(questions->>'schooltext'), submit_date DESC
      SQL
    end
  end
end
