# frozen_string_literal: true

module PaymentProviderCustomers
  class BaseCustomer < ApplicationRecord
    self.table_name = 'payment_provider_customers'

    belongs_to :customer
    belongs_to :payment_provider, optional: true, class_name: 'PaymentProviders::BaseProvider'

    has_many :payments

    def push_to_settings(key:, value:)
      self.settings ||= {}
      settings[key] = value
    end

    def get_from_settings(key)
      (settings || {})[key]
    end

    def sync_with_provider
      get_from_settings('sync_with_provider')
    end

    def sync_with_provider=(sync_with_provider)
      push_to_settings(key: 'sync_with_provider', value: sync_with_provider)
    end
  end
end
