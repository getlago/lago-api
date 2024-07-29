# frozen_string_literal: true

class PayableGroup < ApplicationRecord
  include PaperTrailTraceable

  belongs_to :customer, -> { with_discarded }

  has_many :invoices
  has_many :payments, as: :payable

  PAYMENT_STATUS = %i[pending succeeded failed].freeze

  enum payment_status: PAYMENT_STATUS, _prefix: :payment
end
