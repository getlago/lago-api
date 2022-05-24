# frozen_string_literal: true

class Credit < ApplicationRecord
  include Currencies

  belongs_to :invoice
  belongs_to :applied_coupon

  has_one :coupon, through: :applied_coupon

  validates :amount_currency, inclusion: { in: currency_list }
end
