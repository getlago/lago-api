# frozen_string_literal: true

module Integrations
  class NetsuiteIntegration < BaseIntegration
    validates :connection_id, :client_secret, :client_id, :account_id, presence: true

    settings_accessors :client_id, :account_id, :sync_credit_notes, :sync_invoices, :sync_payments, :sync_sales_orders
    secrets_accessors :connection_id, :client_secret
  end
end
