require 'fileutils'
require 'jekyll'
require 'net/http'
require 'tempfile'
require 'yaml'
require 'unicode_normalize/normalize'
require_relative '../bikebuspdx'
require_relative '../bikebuspdx/webp'
require 'addressable/uri'

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
      if Bikebuspdx::PREPARE_FOR_JOTFORM_TRIM
        yml = <<~DOC
          # Keys are:
          # name: Required. Name of the bike bus, like 'Alameda'
          # slug: Required. Short slug for the URL and other purposes.
          # content: Optional. Markdown content to render above the links.
          # link_text: Optional. Text for the top link. Usually 'Website' or 'Signup Form'.
          # link_href: Optional: Href for the top link.
          # image: Optional. Path to image, like /assets/images/mybikebus.jpg.
          # map_href: Required: Href for the 'Route Map' link and when you click on the route image.
          # map_image: Optional. Default to /assets/images/route-{slug}.png.
          #   If using a different route image (like a jpeg), set this.
          # map_image2: Optional, usually an alternative language for map_image.
          # email: mybikebus@gmail.com
          # instagram: mybikebus
          # bluesky: mybikebus
          # unlist: If true, hide this bike bus. Generally used for the dynamic form data, to remove a school
        DOC
        yml += "\n" + YAML.dump(merged)
        buses_file = Bikebuspdx::SRC / '_data/buses.yml'
        buses_file.write(yml)
        return
      end
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
          kvps = include_data.map { |k, v| "#{k}=#{quote_attr(v)} " }.join(' ')
          file.content = "{% include bus-minisite-content.html #{kvps} %}"
          file.output
        end
      end
    end

    # Liquid's include tag parser only accepts an attribute value wrapped in
    # single or double quotes, with no way to escape a quote char inside it.
    # Values here come from free-text form submissions (e.g. "New route for
    # '26-'27"), so pick whichever quote char doesn't appear in the value,
    # falling back to stripping double quotes if both are present.
    def quote_attr(v)
      s = v.to_s
      return "\"#{s}\"" unless s.include?('"')
      return "'#{s}'" unless s.include?("'")
      "\"#{s.gsub('"', '')}\""
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
      if (s = (h['bluesky'] || '')).length > 0
        s = s.delete_prefix("https://bsky.app/profile/")
        s = s.delete_prefix('@')
        h['bluesky'] = s
      end
      if (s = (h['instagram'] || '')).length > 0
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
            "?query_base64=" + Base64.urlsafe_encode64(self.select_sql) +
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
      # Jotform location header can return utf-8, rather than ascii, so normalize it to a valid url.
      url = Addressable::URI.parse(url).normalize.to_s
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

    def webhookdb_table = @webhookdb_table ||= Bikebuspdx::WEBHOOKDB_TABLE
    def webhookdb_org = @webhookdb_org ||= Bikebuspdx::WEBHOOKDB_ORG
    def webhookdb_conn_url = @webhookdb_conn_url ||= Bikebuspdx::WEBHOOKDB_CONNECTION_URL
    def webhookdb_hash = @webhookdb_hash ||= Digest::SHA256.hexdigest(self.webhookdb_conn_url)
    def form_update_secret = @form_update_secret ||= Bikebuspdx::FORM_UPDATE_SECRET
    # True to use local copies of images. Should only be used locally during development
    # to avoid pulling images every time the server starts.
    # Do not use in production, since it'd potentially cause stale images to be used.
    def use_local_images = @use_local_images ||= Bikebuspdx::USE_LOCAL_IMAGES

    # Jotform key of the radio field that marks a submission as a partial
    # update: a value containing the string 'Partial' counts as partial,
    # anything else (including a missing key, e.g. submissions from before
    # this field existed) is treated as a full update.
    PARTIAL_UPDATE_FIELD = 'updatetype'

    # Builds a "latest non-blank value wins" expression for a jsonb field,
    # scoped to whatever row set the surrounding query's FROM/GROUP BY defines.
    # Blank string is treated the same as NULL, matching clean_buses's semantics.
    def field_agg(json_expr)
      blank_to_null = "NULLIF(#{json_expr}, '')"
      "(array_agg(#{blank_to_null} ORDER BY submit_date DESC) " \
        "FILTER (WHERE #{blank_to_null} IS NOT NULL))[1]"
    end

    def select_sql
      @select_sql ||= <<~SQL
        WITH candidates AS (
            SELECT
                *,
                CASE
                    -- Prefer to use schooltext if set, since it's otherwise too easy to
                    -- select a dropdown school and accidentally stomp on it.
                    WHEN questions->>'schooltext' != '' THEN questions->>'schooltext'
                    ELSE questions->>'school' END
                    AS resolved_name,
                COALESCE(questions->>'#{PARTIAL_UPDATE_FIELD}', '') LIKE '%Partial%' AS is_partial
            FROM #{webhookdb_table}
            WHERE questions->>'password' = '#{form_update_secret}'
        ),
        -- The base layer: each school's latest full (non-partial) submission.
        base AS (
            SELECT DISTINCT ON (lower(questions->>'school'), lower(questions->>'schooltext'))
                questions->>'school' AS school,
                questions->>'schooltext' AS schooltext,
                submit_date AS base_submit_date
            FROM candidates
            WHERE NOT is_partial
            ORDER BY lower(questions->>'school'), lower(questions->>'schooltext'), submit_date DESC
        ),
        -- The base row itself, plus every partial submission for that school
        -- submitted after the base. Schools with no base row are dropped,
        -- same as the old query would drop a school with no submissions.
        layered AS (
            SELECT c.*
            FROM candidates c
            JOIN base b
                ON lower(b.school) = lower(c.questions->>'school')
               AND lower(b.schooltext) = lower(c.questions->>'schooltext')
               AND c.submit_date >= b.base_submit_date
        )
        SELECT
            (array_agg(resolved_name ORDER BY submit_date DESC))[1] AS name,
            #{field_agg("questions->>'maintext'")} AS content,
            #{field_agg("questions->>'websitelabel'")} AS link_text,
            #{field_agg("questions->>'websitelink'")} AS link_href,
            #{field_agg("questions->'headerimage'->>0")} AS image,
            #{field_agg("questions->'image1'->>0")} AS map_image,
            #{field_agg("questions->'image2'->>0")} AS map_image2,
            #{field_agg("questions->>'routemaplink'")} AS map_href,
            #{field_agg("questions->>'unlist'")} AS unlist,
            #{field_agg("questions->>'email'")} AS email,
            #{field_agg("questions->>'bluesky'")} AS bluesky,
            #{field_agg("questions->>'instagram'")} AS instagram
        FROM layered
        GROUP BY lower(questions->>'school'), lower(questions->>'schooltext')
        ORDER BY name
      SQL
    end
  end
end
