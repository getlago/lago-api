# frozen_string_literal: true

class PaymentReceipt < ApplicationRecord
  belongs_to :payment

  scope :for_organization, lambda { |organization|
    payables_join = ActiveRecord::Base.sanitize_sql_array([
      <<~SQL,
        INNER JOIN payments
          ON payments.id = payment_receipts.payment_id
        LEFT JOIN invoices
          ON invoices.id = payments.payable_id
          AND payments.payable_type = 'Invoice'
          AND invoices.organization_id = :org_id
          AND invoices.status IN (:visible_statuses)
        LEFT JOIN payment_requests
          ON payment_requests.id = payments.payable_id
          AND payments.payable_type = 'PaymentRequest'
          AND payment_requests.organization_id = :org_id
      SQL
      {org_id: organization.id, visible_statuses: Invoice::VISIBLE_STATUS.values}
    ])
    joins(payables_join)
      .where("invoices.id IS NOT NULL OR payment_requests.id IS NOT NULL")
  }
end

# == Schema Information
#
# Table name: payment_receipts
#
#  id         :uuid             not null, primary key
#  number     :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  payment_id :uuid             not null
#
# Indexes
#
#  index_payment_receipts_on_payment_id  (payment_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (payment_id => payments.id)
#
