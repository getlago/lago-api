# frozen_string_literal: true

class Plan < ApplicationRecord
  belongs_to :organization

  has_many :charges, dependent: :destroy
  has_many :billable_metrics, through: :charges
  has_many :subscriptions

  FREQUENCIES = %i[
    weekly
    monthly
    yearly
  ].freeze

  BILLING_PERIODS = %i[
    beginning_of_month
    end_of_month
    subscruption_date
  ].freeze

  enum frequency: FREQUENCIES
  enum billing_period: BILLING_PERIODS

  validates :name, presence: true
  validates :code, presence: true, uniqueness: { scope: :organization_id }
end
