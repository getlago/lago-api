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

  # A payment request counts when it covers at least one catalog invoice.
  scope :product_catalog, -> {
    catalog_invoices = Invoice.product_catalog.select(:id)
    catalog_payment_requests = PaymentRequest::AppliedInvoice.where(invoice_id: catalog_invoices).select(:payment_request_id)
    catalog_payments = Payment.where(payable_type: "Invoice", payable_id: catalog_invoices)
      .or(Payment.where(payable_type: "PaymentRequest", payable_id: catalog_payment_requests))

    where(payment_id: catalog_payments.select(:id))
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
