# frozen_string_literal: true

module PaymentProviderCustomers
  class BaseCustomer < ApplicationRecord
    include PaperTrailTraceable

    self.table_name = 'payment_provider_customers'

    belongs_to :customer
    belongs_to :payment_provider, optional: true, class_name: 'PaymentProviders::BaseProvider'

    has_many :payments
    has_many :refunds, foreign_key: :payment_provider_customer_id

    validates :customer_id, uniqueness: { scope: :type }

    def push_to_settings(key:, value:)
      self.settings ||= {}
      settings[key] = value
    end

    def get_from_settings(key)
      (settings || {})[key]
    end

    def provider_mandate_id
      get_from_settings('provider_mandate_id')
    end

    def provider_mandate_id=(provider_mandate_id)
      push_to_settings(key: 'provider_mandate_id', value: provider_mandate_id)
    end

    def provider_payment_methods
      nil
    end

    def sync_with_provider
      get_from_settings('sync_with_provider')
    end

    def sync_with_provider=(sync_with_provider)
      push_to_settings(key: 'sync_with_provider', value: sync_with_provider)
    end
  end
end
