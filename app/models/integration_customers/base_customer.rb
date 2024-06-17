# frozen_string_literal: true

module IntegrationCustomers
  class BaseCustomer < ApplicationRecord
    include PaperTrailTraceable
    include SettingsStorable

    self.table_name = 'integration_customers'

    belongs_to :customer
    belongs_to :integration, class_name: 'Integrations::BaseIntegration'

    validates :customer_id, uniqueness: {scope: :type}

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
