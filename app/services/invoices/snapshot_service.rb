# frozen_string_literal: true

module Invoices
  # Stamps on the invoice the connection of each category it is issued under, so payments,
  # tax retries and accounting/CRM syncs keep targeting it even when the routing changes later.
  # A category that resolves to no connection gets no row.
  class SnapshotService < BaseService
    Result = BaseResult[:invoice]

    def initialize(invoice:, connections:)
      @invoice = invoice
      @connections = connections

      super
    end

    def call
      result.invoice = invoice
      return result unless connections

      connections.each do |routing|
        next if routing.connection_id.nil?

        invoice.invoice_connections.create!(
          organization_id: invoice.organization_id,
          category: routing.category,
          **connection_attributes(routing)
        )
      end

      result
    end

    private

    attr_reader :invoice, :connections

    def connection_attributes(routing)
      if routing.category == InvoiceConnection::CATEGORIES[:payment]
        {payment_provider_customer_id: routing.connection_id}
      else
        {integration_customer_id: routing.connection_id}
      end
    end
  end
end
