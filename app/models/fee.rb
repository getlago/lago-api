# frozen_string_literal: true

class Fee < ApplicationRecord
  include Currencies

  belongs_to :invoice, optional: true
  belongs_to :charge, -> { with_discarded }, optional: true
  belongs_to :add_on, -> { with_discarded }, optional: true
  belongs_to :applied_add_on, optional: true
  belongs_to :subscription, optional: true
  belongs_to :charge_filter, -> { with_discarded }, optional: true
  belongs_to :group, -> { with_discarded }, optional: true
  belongs_to :invoiceable, polymorphic: true, optional: true
  belongs_to :true_up_parent_fee, class_name: 'Fee', optional: true

  has_one :adjusted_fee, dependent: :nullify
  has_one :customer, through: :subscription
  has_one :organization, through: :invoice
  has_one :billable_metric, -> { with_discarded }, through: :charge
  has_one :true_up_fee, class_name: 'Fee', foreign_key: :true_up_parent_fee_id, dependent: :destroy

  has_many :credit_note_items, dependent: :destroy
  has_many :credit_notes, through: :credit_note_items

  has_many :applied_taxes, class_name: 'Fee::AppliedTax', dependent: :destroy
  has_many :taxes, through: :applied_taxes

  monetize :amount_cents
  monetize :taxes_amount_cents, with_model_currency: :currency
  monetize :total_amount_cents
  monetize :unit_amount_cents, disable_validation: true, allow_nil: true, with_model_currency: :currency

  # TODO: Deprecate add_on type in the near future
  FEE_TYPES = %i[charge add_on subscription credit commitment].freeze
  PAYMENT_STATUS = %i[pending succeeded failed refunded].freeze

  enum fee_type: FEE_TYPES
  enum payment_status: PAYMENT_STATUS

  validates :amount_currency, inclusion: { in: currency_list }
  validates :units, numericality: { greated_than_or_equal_to: 0 }
  validates :events_count, numericality: { greated_than_or_equal_to: 0 }, allow_nil: true
  validates :true_up_fee_id, presence: false, unless: :charge?
  validates :total_aggregated_units, presence: true, if: :charge?

  scope :subscription_kind, -> { where(fee_type: :subscription) }
  scope :charge_kind, -> { where(fee_type: :charge) }

  # NOTE: pay_in_advance fees are not be linked to any invoice, but add_on fees does not have any subscriptions
  #       so we need a bit of logic to find the fee in the right organization scope
  scope :from_organization,
        lambda { |organization|
          left_joins(:invoice)
            .left_joins(subscription: :customer)
            .where('COALESCE(invoices.organization_id, customers.organization_id) = ?', organization.id)
        }

  def item_id
    return billable_metric.id if charge?
    return add_on.id if add_on?
    return invoiceable_id if credit?

    subscription_id
  end

  def item_type
    return BillableMetric.name if charge?
    return AddOn.name if add_on?
    return WalletTransaction.name if credit?

    Subscription.name
  end

  def item_code
    return billable_metric.code if charge?
    return add_on.code if add_on?
    return fee_type if credit?

    subscription.plan.code
  end

  def item_name
    return billable_metric.name if charge?
    return add_on.name if add_on?
    return fee_type if credit?

    subscription.plan.name
  end

  def invoice_name
    return invoice_display_name if invoice_display_name.present?
    return charge.invoice_display_name.presence || billable_metric.name if charge?
    return add_on.invoice_name if add_on?
    return fee_type if credit?

    subscription.plan.invoice_display_name
  end

  def group_name
    charge&.group_properties&.find_by(group:)&.invoice_display_name || group&.name
  end

  def grouped_by_display
    return '' unless charge?
    return '' if charge.properties['grouped_by'].blank?

    " • #{grouped_by.values.join(' • ')}"
  end

  def invoice_sorting_clause
    base_clause = "#{invoice_name} #{group_name}".downcase

    return base_clause unless charge?
    return base_clause unless charge.standard?
    return base_clause if charge.properties['grouped_by'].blank?

    "#{invoice_name} #{grouped_by.values.join} #{group_name}".downcase
  end

  def currency
    amount_currency
  end

  def sub_total_excluding_taxes_amount_cents
    amount_cents - precise_coupons_amount_cents
  end

  def total_amount_cents
    amount_cents + taxes_amount_cents
  end
  alias total_amount_currency currency

  def creditable_amount_cents
    amount_cents - credit_note_items.sum(:amount_cents)
  end

  # There are add_on type and one_off type so in order not to mix those two types with associations,
  # this method is added to handle it. In the near future we will deprecate add_on type and remove this method
  def add_on
    return @add_on if defined? @add_on

    return super if add_on_id.present?
    return unless add_on?

    @add_on = AddOn.with_discarded.find_by(id: applied_add_on.add_on_id)
  end
end
