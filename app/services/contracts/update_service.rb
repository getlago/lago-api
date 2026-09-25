# frozen_string_literal: true

module Contracts
  # Edits a contract's authoring fields. A pending contract is fully editable,
  # and changing its plan re-materialises its rate cards onto the contract.
  # Once active, its pricing and schedule are signed: only the administrative
  # fields in EDITABLE_WHILE_ACTIVE can change, and a locked field is accepted
  # only when it carries the value already stored. The end date can come
  # forward but not move later. Finished contracts are read-only. No billing
  # side-effects — lifecycle transitions live in their own services, and
  # bringing the end date in does not reschedule card clocks: that billing
  # cutoff belongs to the billing engine, as for Contracts::TerminateService.
  class UpdateService < BaseService
    include CustomerTimezone
    include SettingsResolvable

    # An allowlist, so a field added later starts locked on active contracts.
    EDITABLE_WHILE_ACTIVE = %i[
      name ended_at purchase_order_number billing_entity_id
      consolidate_invoice payment_method invoice_custom_section
    ].freeze

    Result = BaseResult[:contract, :payment_method]

    def initialize(contract:, params:)
      @contract = contract
      @params = params.to_h.with_indifferent_access
      super
    end

    def call
      return result.not_found_failure!(resource: "contract") unless contract

      unless Contract::LIVE_STATUSES.include?(contract.status)
        return result.single_validation_failure!(field: :contract, error_code: "contract_locked")
      end

      if params[:plan_code].present? && catalog_plan.nil?
        return result.not_found_failure!(resource: "plan")
      end

      if (failure = settings_references_failure)
        return failure
      end

      # Reject malformed dates, but let an explicit null clear the field. A bare
      # present? check would treat false or "" as absent, silently clearing the
      # column instead of rejecting the bad value.
      %i[billing_anchor_date started_at ended_at].each do |field|
        next unless params.key?(field)
        next if params[field].nil?

        unless Utils::Datetime.valid_format?(params[field])
          return result.single_validation_failure!(field:, error_code: "value_is_invalid")
        end
      end

      if contract.active? && locked_field_changed?
        return result.single_validation_failure!(field: :contract, error_code: "contract_locked")
      end

      if contract.active? && extends_end_date?
        return result.single_validation_failure!(field: :ended_at, error_code: "cannot_be_extended")
      end

      # A window that already closed would never terminate — reject it. A
      # resend of the stored end date sets no new window, even once it passed.
      if params[:ended_at].present? && ended_at_in_customer_timezone <= Time.current &&
          ended_at_in_customer_timezone.to_i != contract.ended_at&.to_i
        return result.single_validation_failure!(field: :ended_at, error_code: "already_ended")
      end

      plan_changed = params.key?(:plan_code) && catalog_plan != contract.catalog_plan

      ActiveRecord::Base.transaction do
        contract.name = params[:name] if params.key?(:name)
        contract.ended_at = ended_at_in_customer_timezone if params.key?(:ended_at)
        apply_settings(contract)

        # An active contract only gets here with its locked fields unchanged;
        # writing them back would still version them on a signed contract.
        if contract.pending?
          contract.billing_time = params[:billing_time] if params[:billing_time].present?
          contract.billing_anchor_date = params[:billing_anchor_date] if params.key?(:billing_anchor_date)
          contract.started_at = started_at_in_customer_timezone if params[:started_at].present?
          contract.catalog_plan = catalog_plan if params.key?(:plan_code)
        end
        contract.save!

        # Replace the old plan's materialised cards. The destroy service also
        # discards each card's soft-deletable phases and overrides, which a bare
        # discard_all! would orphan.
        if plan_changed
          contract.applied_rate_cards.to_a.each do |card|
            ContractRateCards::DestroyService.call!(contract_rate_card: card)
          end
          Contracts::MaterializeRateCardsService.call!(contract:) if contract.catalog_plan
        end

        result.contract = contract
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :contract, :params

    delegate :organization, :customer, to: :contract

    def locked_field_changed?
      (params.keys.map(&:to_sym) - EDITABLE_WHILE_ACTIVE).any? { |field| changes?(field) }
    end

    # Forms resend every field, so an unchanged locked value is not an edit.
    def changes?(field)
      case field
      when :plan_code
        catalog_plan != contract.catalog_plan
      when :billing_time
        params[:billing_time].present? && params[:billing_time].to_s != contract.billing_time
      when :started_at
        params[:started_at].present? && started_at_in_customer_timezone.to_i != contract.started_at.to_i
      when :billing_anchor_date
        # A blank stored anchor falls back to the start date, which a form shows.
        [contract.billing_anchor_date, contract.effective_billing_anchor_date].exclude?(params[:billing_anchor_date]&.to_date)
      else
        true
      end
    end

    # Card clocks stop at the current end date and nothing restarts them yet,
    # so moving an active contract's end later, or clearing it, would silently
    # stop its billing.
    def extends_end_date?
      return false if !params.key?(:ended_at) || contract.ended_at.nil?

      params[:ended_at].nil? || ended_at_in_customer_timezone.to_i > contract.ended_at.to_i
    end

    # The contract keeps its plan even once discarded, so a resend of the
    # current code resolves to it instead of looking up kept plans.
    def catalog_plan
      return @catalog_plan if defined?(@catalog_plan)

      @catalog_plan = if params[:plan_code].blank?
        nil
      elsif params[:plan_code] == contract.catalog_plan&.code
        contract.catalog_plan
      else
        organization.catalog_plans.find_by(code: params[:plan_code])
      end
    end

    # Raw source values for the CustomerTimezone *_in_customer_timezone readers.
    def started_at
      params[:started_at].presence
    end

    def ended_at
      params[:ended_at].presence
    end
  end
end
