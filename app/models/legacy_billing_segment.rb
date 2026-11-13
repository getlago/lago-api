# frozen_string_literal: true

# Read-only access to billing segments written before billing operations became
# the authority for scheduled contract billing.
class LegacyBillingSegment < ApplicationRecord
  self.table_name = "billing_segments"

  STATUSES = {pending: "pending", processing: "processing", done: "done", failed: "failed"}.freeze

  belongs_to :invoice, optional: true

  enum :status, STATUSES, validate: true, prefix: true

  def readonly?
    true
  end
end

# == Schema Information
#
# Table name: billing_segments
# Database name: primary
#
#  id                    :uuid             not null, primary key
#  billing_at            :datetime         not null
#  currency              :string           not null
#  cycle_started_at      :datetime         not null
#  ended_at              :datetime         not null
#  proration_ratio       :decimal(30, 10)  default(1.0), not null
#  rate_properties       :jsonb            not null
#  started_at            :datetime         not null
#  status                :enum             default("pending"), not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  contract_id           :uuid             not null
#  contract_rate_card_id :uuid             not null
#  customer_id           :uuid             not null
#  invoice_id            :uuid
#  organization_id       :uuid             not null
#  pricing_unit_id       :uuid
#  rate_card_rate_id     :uuid
#  rate_override_id      :uuid
#
# Indexes
#
#  billing_segments_no_overlapping_periods                (organization_id, contract_id, customer_id, contract_rate_card_id, tsrange(started_at, ended_at, '[]'::text)) USING gist
#  idx_on_contract_id_billing_at_status_3588bfae7a        (contract_id,billing_at,status)
#  index_billing_segments_on_card_and_cycle               (contract_rate_card_id,cycle_started_at)
#  index_billing_segments_on_card_and_period              (contract_rate_card_id,started_at) UNIQUE
#  index_billing_segments_on_contract_id                  (contract_id)
#  index_billing_segments_on_contract_rate_card_id        (contract_rate_card_id)
#  index_billing_segments_on_customer_awaiting_invoicing  (status,customer_id) WHERE (status = ANY (ARRAY['pending'::billing_segment_status, 'processing'::billing_segment_status]))
#  index_billing_segments_on_customer_id                  (customer_id)
#  index_billing_segments_on_invoice_id                   (invoice_id)
#  index_billing_segments_on_organization_id              (organization_id)
#  index_billing_segments_on_rate_override_id             (rate_override_id)
#
# Foreign Keys
#
#  fk_rails_...  (contract_id => contracts.id)
#  fk_rails_...  (contract_rate_card_id => contract_rate_cards.id)
#  fk_rails_...  (customer_id => customers.id)
#  fk_rails_...  (invoice_id => invoices.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (pricing_unit_id => pricing_units.id)
#  fk_rails_...  (rate_card_rate_id => rate_card_rates.id)
#  fk_rails_...  (rate_override_id => rate_overrides.id)
#
