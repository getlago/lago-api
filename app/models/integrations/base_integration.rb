# frozen_string_literal: true

module Integrations
  class BaseIntegration < ApplicationRecord
    include PaperTrailTraceable

    self.table_name = 'integrations'

    belongs_to :organization

    encrypts :secrets

    validates :code, uniqueness: { scope: :organization_id }
    validates :name, presence: true

    def secrets_json
      JSON.parse(secrets || '{}')
    end

    def push_to_secrets(key:, value:)
      self.secrets = secrets_json.merge(key => value).to_json
    end

    def get_from_secrets(key)
      secrets_json[key.to_s]
    end

    def push_to_settings(key:, value:)
      self.settings ||= {}
      settings[key] = value
    end

    def get_from_settings(key)
      (settings || {})[key]
    end
  end
end
