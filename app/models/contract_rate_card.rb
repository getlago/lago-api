# frozen_string_literal: true

class ContractRateCard < ApplicationRecord
  include PaperTrailTraceable
  include Discard::Model
  include PreloadableAggregations

  self.discard_column = :deleted_at
  # The contract end date is the only end of a card; drop once released.
  self.ignored_columns += %w[ended_date]
  self.ignored_columns += %w[units]
  self.ignored_columns += %w[next_billing_at]

  belongs_to :organization
  belongs_to :contract
  belongs_to :rate_card, -> { with_discarded }

  has_one :product, through: :rate_card

  has_many :rate_phases, -> { order(:position) }
  has_many :terms, -> { order(:effective_date, :created_at, :id) }, class_name: "ContractRateCardTerm", inverse_of: :contract_rate_card
  has_many :billing_operations
  has_many :fees

  preloadable_aggregation :billing_operation_clock, default: {} do |ids|
    BillingOperation
      .where(contract_rate_card_id: ids)
      .group(:contract_rate_card_id)
      .pluck(
        :contract_rate_card_id,
        Arel.sql("MIN(billing_at) FILTER (WHERE processed_at IS NULL AND cancelled_at IS NULL)"),
        Arel.sql("COUNT(*) > 0")
      )
      .to_h do |id, pending_at, has_chain|
        [id, {billing_at: pending_at, has_chain:}]
      end
  end

  validates :billing_anchor_date, presence: true
  validates :effective_date, presence: true
  validates :rate_card_id, uniqueness: {scope: :contract_id, conditions: -> { where(deleted_at: nil) }}

  default_scope -> { kept }

  # Only a priced card owes anything: a period with no price is not one to be paid for.
  scope :priced, -> { where(rate_card_id: RateCardRate.select(:rate_card_id)) }

  # Only a card that starts before its contract ends has a period to owe anything in. Bringing
  # the end forward, planned or by a termination, can leave one starting after it.
  scope :starting_before_contract_end, -> {
    joins(contract: {customer: :billing_entity}).where(
      "LEAST(contracts.ended_at, contracts.terminated_at) IS NULL OR " \
      "LEAST(contracts.ended_at, contracts.terminated_at) AT TIME ZONE 'UTC' > " \
      "(contract_rate_cards.effective_date::timestamp AT TIME ZONE " \
      "COALESCE(customers.timezone, billing_entities.timezone, 'UTC'))"
    )
  }

  scope :eligible_for_operation_scheduling, ->(timestamp) {
    priced
      .starting_before_contract_end
      .joins(contract: {customer: :billing_entity})
      .where(contracts: {status: Contract::BILLABLE_STATUSES, started_at: ..timestamp})
      .where(customers: {deleted_at: nil})
  }

  def next_billing_at
    clock = billing_operation_clock
    return clock[:billing_at] if clock[:billing_at]
    return if clock[:has_chain]

    build = Billing::RateCards::BuildScheduleService.call(contract_rate_card: self)
    return unless build.success?

    target = Billing::RateCards::Schedule::BILLING_TARGET.fetch(
      periodic_billing_action.present? ? :current : :next
    )
    build.schedule.billing_at(timestamp: Time.current, target:)
  end

  # A card seeded from its contract carries the contract's explicit anchor, or
  # its own start day when the contract set none: an anchor matching what it
  # would have inherited follows the contract, any other was set on the card.
  def inherited_billing_anchor?(contract_billing_anchor_date)
    billing_anchor_date == (contract_billing_anchor_date || effective_date)
  end

  # NOTE: Metered advance billing has no periodic action unless it renews displayed recurring usage
  # or regroups paid fees. Otherwise, usage events trigger billing and this returns nil.
  def periodic_billing_action
    rate = rate_card
    product = rate.product
    actions = BillingOperation::ACTION_TYPES

    if product.fixed?
      case rate.billing_timing
      when "advance" then actions.fetch(:renew_fixed_advance)
      when "arrears" then actions.fetch(:close_fixed_arrears)
      end
    elsif rate.advance? && rate.display_on_invoice? && product.metered? && product.billable_metric&.recurring?
      actions.fetch(:renew_recurring_metered_advance)
    elsif rate.advance? && rate.regroup_paid_fees_invoice?
      actions.fetch(:regroup_paid_fees)
    elsif product.metered? && rate.arrears?
      actions.fetch(:close_metered_arrears)
    end
  end

  def edit_error_code
    "contract_locked" unless contract.editable?
  end
end

# == Schema Information
#
# Table name: contract_rate_cards
# Database name: primary
#
#  id                  :uuid             not null, primary key
#  billing_anchor_date :date             not null
#  deleted_at          :datetime
#  effective_date      :date             not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  contract_id         :uuid             not null
#  organization_id     :uuid             not null
#  rate_card_id        :uuid             not null
#
# Indexes
#
#  index_contract_rate_cards_by_cursor                  (contract_id,created_at DESC,id DESC) WHERE (deleted_at IS NULL)
#  index_contract_rate_cards_on_contract_and_rate_card  (contract_id,rate_card_id) UNIQUE WHERE (deleted_at IS NULL)
#  index_contract_rate_cards_on_contract_id             (contract_id)
#  index_contract_rate_cards_on_deleted_at              (deleted_at)
#  index_contract_rate_cards_on_id_and_contract_id      (id,contract_id) UNIQUE
#  index_contract_rate_cards_on_next_billing_at         (next_billing_at) WHERE (deleted_at IS NULL)
#  index_contract_rate_cards_on_organization_id         (organization_id)
#  index_contract_rate_cards_on_rate_card_id            (rate_card_id)
#
# Foreign Keys
#
#  fk_rails_...  (contract_id => contracts.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (rate_card_id => rate_cards.id)
#
