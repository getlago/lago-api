# frozen_string_literal: true

class PayableGroup < ApplicationRecord
  include PaperTrailTraceable

  belongs_to :organization
  belongs_to :customer, -> { with_discarded }

  has_many :invoices
  has_many :payments, as: :payable
  has_many :payment_requests, as: :payment_requestable

  PAYMENT_STATUS = %i[pending succeeded failed].freeze

  enum payment_status: PAYMENT_STATUS, _prefix: :payment
end
