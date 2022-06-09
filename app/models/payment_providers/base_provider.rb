# frozen_string_literal: true

module PaymentProviders
  class BaseProvider < ApplicationRecord
    self.table_name = 'payment_providers'

    belongs_to :organization

    encrypts :secrets

    def json_secrets
      JSON.parse(secrests || '{}')
    end

    def push_to_secrests(value)
      self.secrests = json_secrets.merge(value).to_json
    end

    def get_from_secrets(key)
      json_secrets[key.to_s]
    end
  end
end
