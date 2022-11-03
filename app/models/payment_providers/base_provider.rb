# frozen_string_literal: true

module PaymentProviders
  class BaseProvider < ApplicationRecord
    self.table_name = 'payment_providers'

    belongs_to :organization

    has_many :payment_provider_customers,
             dependent: :nullify,
             class_name: 'PaymentProviderCustomers::BaseCustomer',
             foreign_key: :payment_provider_id

    has_many :payments, dependent: :nullify, foreign_key: :payment_provider_id
    has_many :refunds, dependent: :nullify, foreign_key: :payment_provider_id

    encrypts :secrets

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
