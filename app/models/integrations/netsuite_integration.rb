# frozen_string_literal: true

module Integrations
  class NetsuiteIntegration < BaseIntegration
    validates :connection_id, :client_secret, :client_id, :account_id, presence: true

    def connection_id=(connection_id)
      push_to_secrets(key: 'connection_id', value: connection_id)
    end

    def connection_id
      get_from_secrets('connection_id')
    end

    def client_secret=(client_secret)
      push_to_secrets(key: 'client_secret', value: client_secret)
    end

    def client_secret
      get_from_secrets('client_secret')
    end

    def account_id=(value)
      push_to_settings(key: 'account_id', value:)
    end

    def account_id
      get_from_settings('account_id')
    end

    def client_id=(value)
      push_to_settings(key: 'client_id', value:)
    end

    def client_id
      get_from_settings('client_id')
    end

    def sync_credit_notes=(value)
      push_to_settings(key: 'sync_credit_notes', value:)
    end

    def sync_credit_notes
      get_from_settings('sync_credit_notes')
    end

    def sync_invoices=(value)
      push_to_settings(key: 'sync_invoices', value:)
    end

    def sync_invoices
      get_from_settings('sync_invoices')
    end

    def sync_payments=(value)
      push_to_settings(key: 'sync_payments', value:)
    end

    def sync_payments
      get_from_settings('sync_payments')
    end

    def sync_sales_orders=(value)
      push_to_settings(key: 'sync_sales_orders', value:)
    end

    def sync_sales_orders
      get_from_settings('sync_sales_orders')
    end
  end
end
