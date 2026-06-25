# frozen_string_literal: true

# Thin wrapper around the Meilisearch client and index configuration.
#
# Named `MeilisearchClient` (not `Meilisearch`) to avoid clashing with the
# gem's top-level `Meilisearch` module.
class MeilisearchClient
  INVOICES_INDEX = "invoices"

  INVOICES_SETTINGS = {
    searchable_attributes: %w[
      number
      customer_name
      customer_firstname
      customer_lastname
      customer_legal_name
      customer_external_id
      customer_email
    ],
    filterable_attributes: %w[
      organization_id
      billing_entity_id
      currency
      customer_id
      customer_external_id
      invoice_type
      status
      payment_status
      payment_dispute_lost
      payment_overdue
      self_billed
      issuing_date
      total_amount_cents
      due_amount_cents
      partially_paid
      subscription_ids
      settlement_types
      metadata
      metadata_keys
    ],
    sortable_attributes: %w[issuing_date created_at id],
    # Codes/numbers must match exactly — typo tolerance would make e.g. "2024"
    # fuzzy-match "2023"/"2025" and massively inflate results.
    # Nested setting keys are not snake_case-converted by the client, so use the
    # Meilisearch camelCase key directly.
    typo_tolerance: {disableOnAttributes: %w[number customer_external_id customer_email]},
    pagination: {maxTotalHits: 100_000}
  }.freeze

  class << self
    def enabled?
      ENV["LAGO_MEILISEARCH_URL"].present?
    end

    def client
      return nil unless enabled?

      Meilisearch::Client.new(ENV["LAGO_MEILISEARCH_URL"], ENV["MEILI_MASTER_KEY"])
    end

    def index_name(name)
      prefix = ENV.fetch("LAGO_MEILISEARCH_INDEX_PREFIX", Rails.env)
      [prefix, name].compact_blank.join("_")
    end

    def invoices_index
      client&.index(index_name(INVOICES_INDEX))
    end

    # Idempotently create and configure the invoices index.
    def setup_invoices_index!
      return unless enabled?

      client.create_index(index_name(INVOICES_INDEX), primary_key: "id")
      invoices_index.update_settings(INVOICES_SETTINGS)
    end
  end
end
