# frozen_string_literal: true

class PaymentReceipt < ApplicationRecord
  include ExpiringDocumentUrl

  belongs_to :payment
  belongs_to :organization
  belongs_to :billing_entity

  delegate :customer, to: :payment

  has_one_attached :file
  has_one_attached :xml_file

  expiring_document_urls :file, :xml_file

  # Correlated EXISTS on the payment, so that a receipt only probes the invoices it pays: an `IN`
  # under the `OR` would read the invoices of every organization. A payment request counts when
  # it covers at least one catalog invoice.
  scope :product_catalog, -> {
    payments = Payment.arel_table
    invoices = Invoice.arel_table
    applied_invoices = PaymentRequest::AppliedInvoice.arel_table

    paid_invoice = Invoice.product_catalog.where(invoices[:id].eq(payments[:payable_id]))
    requested_invoice = PaymentRequest::AppliedInvoice
      .where(applied_invoices[:payment_request_id].eq(payments[:payable_id]))
      .where(Invoice.product_catalog.where(invoices[:id].eq(applied_invoices[:invoice_id])).arel.exists)
    catalog_payment = Payment.where(payments[:id].eq(arel_table[:payment_id])).where(
      payments[:payable_type].eq("Invoice").and(paid_invoice.arel.exists)
        .or(payments[:payable_type].eq("PaymentRequest").and(requested_invoice.arel.exists))
    )

    where(catalog_payment.arel.exists)
  }
end

# == Schema Information
#
# Table name: payment_receipts
# Database name: primary
#
#  id                :uuid             not null, primary key
#  number            :string           not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  billing_entity_id :uuid             not null
#  organization_id   :uuid             not null
#  payment_id        :uuid             not null
#
# Indexes
#
#  index_payment_receipts_on_billing_entity_id  (billing_entity_id)
#  index_payment_receipts_on_organization_id    (organization_id)
#  index_payment_receipts_on_payment_id         (payment_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (payment_id => payments.id)
#
