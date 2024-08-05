# frozen_string_literal: true

class ProgressiveBillingTreshold < ApplicationRecord
  include PaperTrailTraceable
  include Currencies

  belongs_to :plan

  monetize :amount_cents

  validates :amount_currency, inclusion: {in: currency_list}
  validates :amount_cents, numericality: {greater_than: 0}
  validates :amount_cents, uniqueness: {scope: %i[plan_id recurring]}
  validates :recurring, uniqueness: {scope: :plan_id}, if: -> { recurring? }
end
