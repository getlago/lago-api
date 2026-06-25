# frozen_string_literal: true

module Invoices
  # Builds the Meilisearch document for a single invoice and upserts it into the
  # invoices index. No-op when Meilisearch is not configured.
  class SearchIndexService < BaseService
    Result = BaseResult

    def initialize(invoice:)
      @invoice = invoice
      super
    end

    def call
      return result unless MeilisearchClient.enabled?

      MeilisearchClient.invoices_index.add_documents([document], "id")
      result
    end

    private

    attr_reader :invoice

    def document
      customer = invoice.customer

      {
        id: invoice.id,
        organization_id: invoice.organization_id,
        billing_entity_id: invoice.billing_entity_id,
        currency: invoice.currency,
        customer_id: invoice.customer_id,
        number: invoice.number,
        invoice_type: invoice.invoice_type,
        status: invoice.status,
        payment_status: invoice.payment_status,
        payment_dispute_lost: invoice.payment_dispute_lost_at.present?,
        payment_overdue: invoice.payment_overdue,
        self_billed: invoice.self_billed,
        issuing_date: invoice.issuing_date&.to_time(:utc)&.to_i,
        created_at: invoice.created_at.to_i,
        total_amount_cents: invoice.total_amount_cents,
        due_amount_cents: invoice.total_amount_cents - invoice.total_paid_amount_cents,
        partially_paid: partially_paid?,
        customer_external_id: customer&.external_id,
        customer_name: customer&.name,
        customer_firstname: customer&.firstname,
        customer_lastname: customer&.lastname,
        customer_legal_name: customer&.legal_name,
        customer_email: customer&.email,
        subscription_ids: invoice.invoice_subscriptions.pluck(:subscription_id).uniq,
        settlement_types: invoice.invoice_settlements.distinct.pluck(:settlement_type),
        metadata: invoice.metadata.map { |meta| "#{meta.key}::#{meta.value}" },
        metadata_keys: invoice.metadata.map(&:key)
      }
    end

    def partially_paid?
      invoice.total_amount_cents > invoice.total_paid_amount_cents && invoice.total_paid_amount_cents.positive?
    end
  end
end
