# frozen_string_literal: true

module SubscriptionRateCards
  # Edits a subscription entry. While the subscription is pending the entry is
  # freely editable (authoring window). Once active, only the units can change
  # — as a quantity, not a price — and every change is recorded by versioning
  # the entry: the current row is closed (ended_at) and a successor row opens
  # at the effective time, carrying the phases and overrides. The timeline of
  # rows is the units history the billing engine prices per period.
  class UpdateService < BaseService
    Result = BaseResult[:subscription_rate_card]

    APPLY_UNITS = %w[now next_billing_period].freeze

    def initialize(subscription_rate_card:, params:)
      @subscription_rate_card = subscription_rate_card
      @params = params.to_h.with_indifferent_access
      super
    end

    def call
      return result.not_found_failure!(resource: "applied_rate_card") unless subscription_rate_card

      # The column is a date and NOT NULL: a malformed or null value would
      # cast to nil and crash on save instead of failing cleanly.
      if params.key?(:billing_anchor_date) && Utils::Datetime.parse_iso8601_date(params[:billing_anchor_date]).nil?
        return result.single_validation_failure!(field: :billing_anchor_date, error_code: "value_is_invalid")
      end

      # A malformed quantity must fail cleanly on both branches; an explicit
      # null stays a valid clear (the column allows it).
      if params.key?(:units) && !params[:units].nil? && BigDecimal(params[:units].to_s, exception: false).nil?
        return result.single_validation_failure!(field: :units, error_code: "value_is_invalid")
      end

      if subscription_rate_card.subscription.pending?
        return update_pending_entry
      end

      if locked_field_changed
        return result.single_validation_failure!(field: locked_field_changed, error_code: "subscription_locked")
      end

      return result_with_current unless units_changed?

      unless params.key?(:apply_units)
        return result.single_validation_failure!(field: :apply_units, error_code: "value_is_mandatory")
      end

      unless APPLY_UNITS.include?(params[:apply_units])
        return result.single_validation_failure!(field: :apply_units, error_code: "value_is_invalid")
      end

      version_units!
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :subscription_rate_card, :params

    def update_pending_entry
      subscription_rate_card.units = params[:units] if params.key?(:units)
      subscription_rate_card.billing_anchor_date = params[:billing_anchor_date] if params.key?(:billing_anchor_date)

      # The billing clock is seeded from the start date, so it follows it.
      if params.key?(:started_at)
        subscription_rate_card.started_at = params[:started_at]
        subscription_rate_card.next_billing_at = params[:started_at]
      end

      subscription_rate_card.save!

      result.subscription_rate_card = subscription_rate_card
      result
    end

    # On an active subscription only the quantity may move; the clock and
    # start date stay signed. Resending unchanged values is always allowed.
    def locked_field_changed
      %i[started_at billing_anchor_date].find do |field|
        next false unless params.key?(field)

        submitted = params[field].to_s
        current = subscription_rate_card.public_send(field)
        submitted != current.to_s && submitted != current&.iso8601.to_s
      end
    end

    def units_changed?
      return false unless params.key?(:units)
      return !subscription_rate_card.units.nil? if params[:units].nil?

      BigDecimal(params[:units].to_s) != subscription_rate_card.units
    end

    def result_with_current
      result.subscription_rate_card = subscription_rate_card
      result
    end

    def effective_at
      return Time.current if params[:apply_units] == "now"

      # The per-entry clock normally points at the upcoming period boundary.
      # If it lags (engine mid-run or not yet processing), the next boundary
      # is effectively now.
      [subscription_rate_card.next_billing_at, Time.current].max
    end

    def version_units!
      at = effective_at

      ActiveRecord::Base.transaction do
        # Re-read before duplicating: the successor inherits next_billing_at, and a stale copy
        # would carry a clock the producer has already advanced, making the successor look due
        # and re-billing the period that was just invoiced.
        subscription_rate_card.reload

        # A newer change supersedes any still-scheduled one.
        subscription_rate_card.subscription.applied_rate_cards
          .where(rate_card_id: subscription_rate_card.rate_card_id)
          .where("started_at > ?", Time.current)
          .find_each { |scheduled| discard_version(scheduled) }

        successor = subscription_rate_card.dup
        successor.units = params[:units]
        successor.started_at = at
        successor.ended_at = nil

        subscription_rate_card.update!(ended_at: at)
        successor.save!

        subscription_rate_card.rate_phases.order(:position).each do |phase|
          copied_override = phase.rate_override&.dup
          copied_override&.save!

          copied_phase = phase.dup
          copied_phase.subscription_rate_card = successor
          copied_phase.rate_override = copied_override
          copied_phase.save!
        end

        # A pay-in-advance rise inside a period that has already been invoiced owes the
        # difference for the days still ahead. Inside the transaction on purpose: a change
        # that is recorded but never billed is silent revenue loss, so if the charge cannot
        # be scheduled the change does not stand either. Returns without doing anything for
        # arrears, for decreases, and for a rise that stays under the watermark.
        BillingCycles::ScheduleAdvanceIncrementService.call!(subscription_rate_card: successor, at:)

        result.subscription_rate_card = successor
      end
    end

    def discard_version(entry)
      phases = entry.rate_phases.to_a
      RateOverride.where(id: phases.filter_map(&:rate_override_id)).discard_all!
      entry.rate_phases.discard_all!
      entry.discard!
    end
  end
end
