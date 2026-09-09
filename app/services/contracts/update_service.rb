# frozen_string_literal: true

module Contracts
  # Edits a pending contract's authoring fields. Pending-only: once the
  # agreement is active it is locked, the same rule rate-card edits follow.
  # Changing the plan re-materialises its rate cards onto the contract. No
  # billing side-effects — lifecycle transitions live in their own services.
  class UpdateService < BaseService
    include CustomerTimezone

    Result = BaseResult[:contract]

    def initialize(contract:, params:)
      @contract = contract
      @params = params.to_h.with_indifferent_access
      super
    end

    def call
      return result.not_found_failure!(resource: "contract") unless contract

      if (error_code = contract.edit_error_code)
        return result.single_validation_failure!(field: :contract, error_code:)
      end

      if params[:plan_code].present? && catalog_plan.nil?
        return result.not_found_failure!(resource: "plan")
      end

      # Reject malformed dates explicitly — they would otherwise cast to nil.
      %i[billing_anchor_date started_at ended_at].each do |field|
        if params[field].present? && !Utils::Datetime.valid_format?(params[field])
          return result.single_validation_failure!(field:, error_code: "value_is_invalid")
        end
      end

      # A window that already closed would never terminate — reject it.
      if params[:ended_at].present? && ended_at_in_customer_timezone <= Time.current
        return result.single_validation_failure!(field: :ended_at, error_code: "already_ended")
      end

      plan_changed = params.key?(:plan_code) && catalog_plan != contract.catalog_plan

      ActiveRecord::Base.transaction do
        contract.name = params[:name] if params.key?(:name)
        contract.billing_time = params[:billing_time] if params[:billing_time].present?
        contract.billing_anchor_date = params[:billing_anchor_date] if params.key?(:billing_anchor_date)
        contract.started_at = started_at_in_customer_timezone if params[:started_at].present?
        contract.ended_at = ended_at_in_customer_timezone if params.key?(:ended_at)
        contract.catalog_plan = catalog_plan if params.key?(:plan_code)
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

    def catalog_plan
      return @catalog_plan if defined?(@catalog_plan)

      @catalog_plan = params[:plan_code].present? ? organization.catalog_plans.find_by(code: params[:plan_code]) : nil
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
