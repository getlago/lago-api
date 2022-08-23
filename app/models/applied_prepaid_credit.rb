# frozen_string_literal: true

class AppliedPrepaidCredit < ApplicationRecord
  include Currencies

  belongs_to :invoice
  belongs_to :wallet_transaction

  has_one :wallet, through: :wallet_transaction

  validates :amount_currency, inclusion: { in: currency_list }
end
