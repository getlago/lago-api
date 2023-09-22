# frozen_string_literal: true

class Plan < ApplicationRecord
  include PaperTrailTraceable
  include Currencies
  include Discard::Model
  self.discard_column = :deleted_at

  belongs_to :organization
  belongs_to :parent, class_name: 'Plan', optional: true

  has_many :charges, dependent: :destroy
  has_many :billable_metrics, through: :charges
  has_many :subscriptions
  has_many :customers, through: :subscriptions
  has_many :children, class_name: 'Plan', foreign_key: :parent_id, dependent: :destroy
  has_many :coupon_targets
  has_many :coupons, through: :coupon_targets
  has_many :invoices, through: :subscriptions

  has_many :applied_taxes, class_name: 'Plan::AppliedTax', dependent: :destroy
  has_many :taxes, through: :applied_taxes

  INTERVALS = %i[
    weekly
    monthly
    yearly
    quarterly
  ].freeze

  enum interval: INTERVALS

  monetize :amount_cents

  validates :name, :code, presence: true
  validates :amount_currency, inclusion: { in: currency_list }
  validates :pay_in_advance, inclusion: { in: [true, false] }
  validate :validate_code_unique

  default_scope -> { kept }
  scope :parents, -> { where(parent_id: nil) }

  def self.ransackable_attributes(_auth_object = nil)
    %w[name code]
  end

  def pay_in_arrear?
    !pay_in_advance
  end

  def attached_to_subscriptions?
    subscriptions.exists?
  end

  def has_trial?
    trial_period.present? && trial_period.positive?
  end

  def invoice_name
    invoice_display_name.presence || name
  end

  # NOTE: Method used to compare plan for upgrade / downgrade on
  #       a same duration basis. It is not intended to be used
  #       directly for billing/invoicing purpose
  def yearly_amount_cents
    return amount_cents if yearly?
    return amount_cents * 12 if monthly?
    return amount_cents * 4 if quarterly?

    amount_cents * 52
  end

  def active_subscriptions_count
    count = subscriptions.active.count
    return count unless children

    count + children.joins(:subscriptions).merge(Subscription.active).select('subscriptions.id').distinct.count
  end

  def customers_count
    count = subscriptions.active.select(:customer_id).distinct.count
    return count unless children

    count + children.joins(:subscriptions).merge(Subscription.active).select(:customer_id).distinct.count
  end

  def draft_invoices_count
    count = subscriptions.joins(:invoices).merge(Invoice.draft).select(:invoice_id).distinct.count
    return count unless children

    count + children.joins(:subscriptions).joins(:invoices).merge(Invoice.draft).select(:invoice_id).distinct.count
  end

  private

  def validate_code_unique
    return unless organization
    return if parent_id?

    plan = organization.plans.parents.where(code:).first
    errors.add(:code, :taken) if plan && plan != self
  end
end
