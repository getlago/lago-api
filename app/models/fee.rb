# frozen_string_literal: true

class Fee < ApplicationRecord
  include Currencies
  include Discard::Model
  self.discard_column = :deleted_at
  default_scope -> { kept }

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
  monetize :precise_amount_cents, with_model_currency: :currency
  monetize :taxes_precise_amount_cents, with_model_currency: :currency
  monetize :precise_total_amount_cents
  monetize :unit_amount_cents, disable_validation: true, allow_nil: true, with_model_currency: :currency

  # TODO: Deprecate add_on type in the near future
  FEE_TYPES = %i[charge add_on subscription credit commitment].freeze
  PAYMENT_STATUS = %i[pending succeeded failed refunded].freeze

  enum fee_type: FEE_TYPES
  enum payment_status: PAYMENT_STATUS, _prefix: :payment

  validates :amount_currency, inclusion: {in: currency_list}
  validates :units, numericality: {greated_than_or_equal_to: 0}
  validates :events_count, numericality: {greated_than_or_equal_to: 0}, allow_nil: true
  validates :true_up_fee_id, presence: false, unless: :charge?
  validates :total_aggregated_units, presence: true, if: :charge?

  scope :subscription_kind, -> { where(fee_type: :subscription) }
  scope :charge_kind, -> { where(fee_type: :charge) }
  scope :commitment_kind, -> { where(fee_type: :commitment) }

  scope :positive_units, -> { where('units > ?', 0) }

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

  def item_description
    return billable_metric.description if charge?
    return add_on.description if add_on?
    return fee_type if credit?

    subscription.plan.description
  end

  def invoice_name
    return invoice_display_name if invoice_display_name.present?
    return charge.invoice_display_name.presence || billable_metric.name if charge?
    return add_on.invoice_name if add_on?
    return fee_type if credit?

    subscription.plan.invoice_display_name
  end

  def filter_display_name(separator: ', ')
    charge_filter&.display_name(separator:)
  end

  def invoice_sorting_clause
    base_clause = "#{invoice_name} #{filter_display_name}".downcase

    return base_clause unless charge?
    return base_clause unless charge.standard?
    return base_clause if charge.properties['grouped_by'].blank?

    "#{invoice_name} #{grouped_by.values.join} #{filter_display_name}".downcase
  end

  def currency
    amount_currency
  end

  def sub_total_excluding_taxes_amount_cents
    amount_cents - precise_coupons_amount_cents
  end

  def sub_total_excluding_taxes_precise_amount_cents
    precise_amount_cents - precise_coupons_amount_cents
  end

  def total_amount_cents
    amount_cents + taxes_amount_cents
  end
  alias_method :total_amount_currency, :currency

  def precise_total_amount_cents
    precise_amount_cents + taxes_precise_amount_cents
  end
  alias_method :precise_total_amount_currency, :currency

  def creditable_amount_cents
    remaining_amount = amount_cents - credit_note_items.sum(:amount_cents)

    return [remaining_amount, invoice.associated_active_wallet&.balance_cents || 0].min if credit?
    remaining_amount
  end

  # There are add_on type and one_off type so in order not to mix those two types with associations,
  # this method is added to handle it. In the near future we will deprecate add_on type and remove this method
  def add_on
    return @add_on if defined? @add_on

    return super if add_on_id.present?
    return unless add_on?

    @add_on = AddOn.with_discarded.find_by(id: applied_add_on.add_on_id)
  end

  def has_charge_filters?
    charge&.filters&.any?
  end
end

# == Schema Information
#
# Table name: fees
#
#  id                                  :uuid             not null, primary key
#  amount_cents                        :bigint           not null
#  amount_currency                     :string           not null
#  amount_details                      :jsonb            not null
#  deleted_at                          :datetime
#  description                         :string
#  events_count                        :integer
#  failed_at                           :datetime
#  fee_type                            :integer
#  grouped_by                          :jsonb            not null
#  invoice_display_name                :string
#  invoiceable_type                    :string
#  pay_in_advance                      :boolean          default(FALSE), not null
#  payment_status                      :integer          default("pending"), not null
#  precise_amount_cents                :decimal(40, 15)  default(0.0), not null
#  precise_coupons_amount_cents        :decimal(30, 5)   default(0.0), not null
#  precise_unit_amount                 :decimal(30, 15)  default(0.0), not null
#  properties                          :jsonb            not null
#  refunded_at                         :datetime
#  succeeded_at                        :datetime
#  taxes_amount_cents                  :bigint           not null
#  taxes_base_rate                     :float            default(1.0), not null
#  taxes_precise_amount_cents          :decimal(40, 15)  default(0.0), not null
#  taxes_rate                          :float            default(0.0), not null
#  total_aggregated_units              :decimal(, )
#  unit_amount_cents                   :bigint           default(0), not null
#  units                               :decimal(, )      default(0.0), not null
#  created_at                          :datetime         not null
#  updated_at                          :datetime         not null
#  add_on_id                           :uuid
#  applied_add_on_id                   :uuid
#  charge_filter_id                    :uuid
#  charge_id                           :uuid
#  group_id                            :uuid
#  invoice_id                          :uuid
#  invoiceable_id                      :uuid
#  pay_in_advance_event_id             :uuid
#  pay_in_advance_event_transaction_id :string
#  subscription_id                     :uuid
#  true_up_parent_fee_id               :uuid
#
# Indexes
#
#  index_fees_on_add_on_id                            (add_on_id)
#  index_fees_on_applied_add_on_id                    (applied_add_on_id)
#  index_fees_on_charge_filter_id                     (charge_filter_id)
#  index_fees_on_charge_id                            (charge_id)
#  index_fees_on_charge_id_and_invoice_id             (charge_id,invoice_id) WHERE (deleted_at IS NULL)
#  index_fees_on_deleted_at                           (deleted_at)
#  index_fees_on_group_id                             (group_id)
#  index_fees_on_invoice_id                           (invoice_id)
#  index_fees_on_invoiceable                          (invoiceable_type,invoiceable_id)
#  index_fees_on_pay_in_advance_event_transaction_id  (pay_in_advance_event_transaction_id) WHERE (deleted_at IS NULL)
#  index_fees_on_subscription_id                      (subscription_id)
#  index_fees_on_true_up_parent_fee_id                (true_up_parent_fee_id)
#
# Foreign Keys
#
#  fk_rails_...  (add_on_id => add_ons.id)
#  fk_rails_...  (applied_add_on_id => applied_add_ons.id)
#  fk_rails_...  (charge_id => charges.id)
#  fk_rails_...  (group_id => groups.id)
#  fk_rails_...  (invoice_id => invoices.id)
#  fk_rails_...  (subscription_id => subscriptions.id)
#  fk_rails_...  (true_up_parent_fee_id => fees.id)
#
