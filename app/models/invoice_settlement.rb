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

  validates :amount_cents, numericality: { greater_than: 0 }
  validates :amount_currency, inclusion: { in: currency_list }
  validates :settlement_type, presence: true
end