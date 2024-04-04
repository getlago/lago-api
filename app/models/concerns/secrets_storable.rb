# frozen_string_literal: true

module SecretsStorable
  extend ActiveSupport::Concern

  included do
    encrypts :secrets
  end

  def secrets_json
    JSON.parse(secrets || '{}')
  end

  def push_to_secrets(key:, value:)
    self.secrets = secrets_json.merge(key => value).to_json
  end

  def get_from_secrets(key)
    secrets_json[key.to_s]
  end
end
