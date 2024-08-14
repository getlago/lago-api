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
end
