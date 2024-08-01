# frozen_string_literal: true

class PaymentRequest < ApplicationRecord
  include PaperTrailTraceable

  belongs_to :customer
  belongs_to :payment, optional: true
  belongs_to :payment_requestable, polymorphic: true

  validates :email, presence: true
  validates :amount_cents, presence: true
  validates :amount_currency, presence: true
end
