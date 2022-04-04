# frozen_string_literal: true

class Fee < ApplicationRecord
  include Currencies

  belongs_to :invoice
  belongs_to :charge
  belongs_to :subscription

  has_one :customer, through: :subscription
  has_one :organization, through: :invoice
  has_one :billable_metric, through: :charge

  monetize :amount_cents
  monetize :vat_amount_cents

  validates :amount_currency, inclusion: { in: currency_list }
  validates :vat_amount_currency, inclusion: { in: currency_list }
end
