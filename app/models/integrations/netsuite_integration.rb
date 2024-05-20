# frozen_string_literal: true

module Integrations
  class NetsuiteIntegration < BaseIntegration
    validates :connection_id, :client_secret, :client_id, :account_id, :script_endpoint_url, presence: true

    settings_accessors :client_id,
      :sync_credit_notes,
      :sync_invoices,
      :sync_payments,
      :sync_sales_orders,
      :script_endpoint_url
    secrets_accessors :connection_id, :client_secret

    def account_id=(value)
      push_to_settings(key: 'account_id', value: value&.downcase&.strip&.split(' ')&.join('-'))
    end

    def account_id
      get_from_settings('account_id')
    end
  end
end
