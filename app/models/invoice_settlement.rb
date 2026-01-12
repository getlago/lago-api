# frozen_string_literal: true

class InvoiceSettlement < ApplicationRecord
  include Currencies

  SETTLEMENT_TYPES = %i[payment credit_note].freeze

  belongs_to :organization
  belongs_to :billing_entity
  belongs_to :target_invoice, class_name: "Invoice"
  belongs_to :source_payment, class_name: "Payment", optional: true
  belongs_to :source_credit_note, class_name: "CreditNote", optional: true

  enum :settlement_type, SETTLEMENT_TYPES

  monetize :amount_cents, with_model_currency: :amount_currency

  validates :amount_cents, numericality: {greater_than: 0}
  validates :amount_currency, inclusion: {in: currency_list}
  validates :settlement_type, presence: true
end

# == Schema Information
#
# Table name: invoice_settlements
# Database name: primary
#
#  id                    :uuid             not null, primary key
#  amount_cents          :bigint           not null
#  amount_currency       :string           not null
#  settlement_type       :string           not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  billing_entity_id     :uuid             not null
#  organization_id       :uuid             not null
#  source_credit_note_id :uuid
#  source_payment_id     :uuid
#  target_invoice_id     :uuid             not null
#
# Indexes
#
#  index_invoice_settlements_on_billing_entity_id      (billing_entity_id)
#  index_invoice_settlements_on_organization_id        (organization_id)
#  index_invoice_settlements_on_source_credit_note_id  (source_credit_note_id)
#  index_invoice_settlements_on_source_payment_id      (source_payment_id)
#  index_invoice_settlements_on_target_invoice_id      (target_invoice_id)
#
# Foreign Keys
#
#  fk_rails_...  (billing_entity_id => billing_entities.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (source_credit_note_id => credit_notes.id)
#  fk_rails_...  (source_payment_id => payments.id)
#  fk_rails_...  (target_invoice_id => invoices.id)
#
