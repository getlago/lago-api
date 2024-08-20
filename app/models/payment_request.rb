# frozen_string_literal: true

class PaymentRequest < ApplicationRecord
  include PaperTrailTraceable

  has_many :payments
  belongs_to :organization
  belongs_to :customer, -> { with_discarded }
  belongs_to :payment_requestable, polymorphic: true

  validates :email, presence: true
  validates :amount_cents, presence: true
  validates :amount_currency, presence: true

  def invoices
    payment_requestable.is_a?(Invoice) ? [payment_requestable] : payment_requestable.invoices
  end
end

# == Schema Information
#
# Table name: payment_requests
#
#  id                       :uuid             not null, primary key
#  amount_cents             :bigint           default(0), not null
#  amount_currency          :string           not null
#  email                    :string           not null
#  payment_requestable_type :string           default("Invoice"), not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  customer_id              :uuid             not null
#  organization_id          :uuid             not null
#  payment_requestable_id   :uuid             not null
#
# Indexes
#
#  idx_on_payment_requestable_type_payment_requestable_b151968780  (payment_requestable_type,payment_requestable_id)
#  index_payment_requests_on_customer_id                           (customer_id)
#  index_payment_requests_on_organization_id                       (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (customer_id => customers.id)
#  fk_rails_...  (organization_id => organizations.id)
#
