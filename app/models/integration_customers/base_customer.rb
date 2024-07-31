# frozen_string_literal: true

module IntegrationCustomers
  class BaseCustomer < ApplicationRecord
    include PaperTrailTraceable
    include SettingsStorable

    self.table_name = 'integration_customers'

    belongs_to :customer
    belongs_to :integration, class_name: 'Integrations::BaseIntegration'

    validates :customer_id, uniqueness: {scope: :type}

    scope :accounting_kind, -> do
      where(type: %w[IntegrationCustomers::NetsuiteCustomer IntegrationCustomers::XeroCustomer])
    end

    settings_accessors :sync_with_provider

    def self.customer_type(type)
      case type
      when 'netsuite'
        'IntegrationCustomers::NetsuiteCustomer'
      when 'okta'
        'IntegrationCustomers::OktaCustomer'
      when 'anrok'
        'IntegrationCustomers::AnrokCustomer'
      when 'xero'
        'IntegrationCustomers::XeroCustomer'
      else
        raise(NotImplementedError)
      end
    end
  end
end

# == Schema Information
#
# Table name: integration_customers
#
#  id                   :uuid             not null, primary key
#  settings             :jsonb            not null
#  type                 :string           not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  customer_id          :uuid             not null
#  external_customer_id :string
#  integration_id       :uuid             not null
#
# Indexes
#
#  index_integration_customers_on_customer_id           (customer_id)
#  index_integration_customers_on_customer_id_and_type  (customer_id,type) UNIQUE
#  index_integration_customers_on_external_customer_id  (external_customer_id)
#  index_integration_customers_on_integration_id        (integration_id)
#
# Foreign Keys
#
#  fk_rails_...  (customer_id => customers.id)
#  fk_rails_...  (integration_id => integrations.id)
#
