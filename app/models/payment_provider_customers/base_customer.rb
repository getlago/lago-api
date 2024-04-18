# frozen_string_literal: true

module PaymentProviderCustomers
  class BaseCustomer < ApplicationRecord
    include PaperTrailTraceable
    include SettingsStorable

    self.table_name = 'payment_provider_customers'

    belongs_to :customer
    belongs_to :payment_provider, optional: true, class_name: 'PaymentProviders::BaseProvider'

    has_many :payments
    has_many :refunds, foreign_key: :payment_provider_customer_id

    validates :customer_id, uniqueness: { scope: :type }

    settings_accessors :provider_mandate_id, :sync_with_provider

    def provider_payment_methods
      nil
    end
  end
end
