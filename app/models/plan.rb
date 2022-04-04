# frozen_string_literal: true

class Plan < ApplicationRecord
  include Currencies

  belongs_to :organization

  has_many :charges, dependent: :destroy
  has_many :billable_metrics, through: :charges
  has_many :subscriptions
  has_many :customers, through: :subscriptions

  FREQUENCIES = %i[
    weekly
    monthly
    yearly
  ].freeze

  BILLING_PERIODS = %i[
    beginning_of_period
    subscription_date
  ].freeze

  enum frequency: FREQUENCIES
  enum billing_period: BILLING_PERIODS

  monetize :amount_cents

  validates :name, presence: true
  validates :code, presence: true, uniqueness: { scope: :organization_id }
  validates :amount_currency, inclusion: { in: currency_list }
end
