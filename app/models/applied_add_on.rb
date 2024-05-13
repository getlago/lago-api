# frozen_string_literal: true

class AppliedAddOn < ApplicationRecord
  include PaperTrailTraceable
  include Currencies

  belongs_to :add_on
  belongs_to :customer

  monetize :amount_cents

  validates :amount_cents, numericality: {greater_than: 0}
  validates :amount_currency, inclusion: {in: currency_list}
end
