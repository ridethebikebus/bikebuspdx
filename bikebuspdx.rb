# frozen_string_literal: true

module Bikebuspdx
  SRC = Pathname(__FILE__).parent

  class << self
    def parse_bool(s)
      return false unless s
      s = s.downcase
      return ['1', 'true', 't', 'yes', 'y', 'on'].include?(s)
    end
  end

  WEBHOOKDB_TABLE = ENV.fetch('WEBHOOKDB_TABLE', 'jotform_webhook_v1_ce87')
  WEBHOOKDB_ORG = ENV.fetch('WEBHOOKDB_ORG', 'bikebuspdx')
  WEBHOOKDB_CONNECTION_URL = ENV.fetch('WEBHOOKDB_CONNECTION_URL', nil)
  FORM_UPDATE_SECRET = ENV.fetch('FORM_UPDATE_SECRET', nil)
  USE_LOCAL_IMAGES = parse_bool(ENV.fetch('USE_LOCAL_IMAGES', nil))

  # If set, save out a new buses.yml file,
  # and rehost images. This must be done before trimming old Jotform responses,
  # which is needed to trim the stored data.
  PREPARE_FOR_JOTFORM_TRIM = parse_bool(ENV.fetch('PREPARE_FOR_JOTFORM_TRIM', nil))
end
