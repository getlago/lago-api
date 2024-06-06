# frozen_string_literal: true

module Integrations
  class XeroIntegration < BaseIntegration
    validates :connection_id, presence: true

    settings_accessors :sync_credit_notes, :sync_invoices, :sync_payments
    secrets_accessors :connection_id
  end
end
