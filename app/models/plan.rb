# frozen_string_literal: true

class Plan < ApplicationRecord
  include Currencies

  belongs_to :organization
  belongs_to :overridden_plan, class_name: 'Plan', optional: true

  has_many :charges, dependent: :destroy
  has_many :billable_metrics, through: :charges
  has_many :subscriptions
  has_many :customers, through: :subscriptions
  has_many :extended_plans, class_name: 'Plan', foreign_key: :overridden_plan_id

  INTERVALS = %i[
    weekly
    monthly
    yearly
  ].freeze

  enum interval: INTERVALS

  monetize :amount_cents

  validates :name, presence: true
  validates :code, presence: true, uniqueness: { scope: :organization_id }
  validates :amount_currency, inclusion: { in: currency_list }

  scope :base, -> { where(overridden_plan_id: nil) }

  def pay_in_arrear?
    !pay_in_advance
  end

  def attached_to_subscriptions?
    subscriptions.exists?
  end

  def deletable?
    !attached_to_subscriptions?
  end

  def has_trial?
    trial_period.present?
  end

  # NOTE: Method used to compare plan for upgrade / downgrade on
  #       a same duration basis. It is not intended to be used
  #       directly for billing/invoicing purpose
  def yearly_amount_cents
    return amount_cents if yearly?
    return amount_cents * 12 if monthly?

    amount_cents * 52
  end
end
