# frozen_string_literal: true

module PaymentProviders
  class BaseProvider < ApplicationRecord
    include PaperTrailTraceable
    include SecretsStorable
    include SettingsStorable

    self.table_name = 'payment_providers'

    belongs_to :organization

    has_many :payment_provider_customers,
             dependent: :nullify,
             class_name: 'PaymentProviderCustomers::BaseCustomer',
             foreign_key: :payment_provider_id

    has_many :payments, dependent: :nullify, foreign_key: :payment_provider_id
    has_many :refunds, dependent: :nullify, foreign_key: :payment_provider_id

    validates :code, uniqueness: { scope: :organization_id }
    validates :name, presence: true

    def webhook_secret=(value)
      push_to_settings(key: 'webhook_secret', value:)
    end

    def webhook_secret
      get_from_settings('webhook_secret')
    end

    def success_redirect_url=(value)
      push_to_settings(key: 'success_redirect_url', value:)
    end

    def success_redirect_url
      get_from_settings('success_redirect_url')
    end
  end
end
