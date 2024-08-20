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

    validates :customer_id, uniqueness: {scope: :type}

    settings_accessors :provider_mandate_id, :sync_with_provider

    def provider_payment_methods
      nil
    end
  end
end

# == Schema Information
#
# Table name: payment_provider_customers
#
#  id                   :uuid             not null, primary key
#  settings             :jsonb            not null
#  type                 :string           not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  customer_id          :uuid             not null
#  payment_provider_id  :uuid
#  provider_customer_id :string
#
# Indexes
#
#  index_payment_provider_customers_on_customer_id_and_type  (customer_id,type) UNIQUE
#  index_payment_provider_customers_on_payment_provider_id   (payment_provider_id)
#  index_payment_provider_customers_on_provider_customer_id  (provider_customer_id)
#
# Foreign Keys
#
#  fk_rails_...  (customer_id => customers.id)
#  fk_rails_...  (payment_provider_id => payment_providers.id)
#
