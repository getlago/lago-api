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
      return result.single_validation_failure!(field: :contract, error_code: "contract_locked") unless contract.editable?

      if params[:plan_code].present? && catalog_plan.nil?
        return result.not_found_failure!(resource: "plan")
      end

      # Date columns: a malformed value would silently cast to nil instead of
      # failing, so formats are rejected explicitly.
      %i[billing_anchor_date started_at ended_at].each do |field|
        if params[field].present? && !Utils::Datetime.valid_format?(params[field])
          return result.single_validation_failure!(field:, error_code: "value_is_invalid")
        end
      end

      # A window that already closed cannot be set: nothing would ever
      # terminate it, leaving a zombie active contract.
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

        # The materialised cards belong to the old plan; a plan change re-derives
        # them from the new one (or leaves the contract plan-less).
        if plan_changed
          contract.applied_rate_cards.discard_all!
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

    # Read through the CustomerTimezone suffix: a naive datetime means the
    # customer's wall clock, and an explicit offset is respected. Nil when
    # the param is absent.
    def started_at
      params[:started_at].presence
    end

    def ended_at
      params[:ended_at].presence
    end
  end
end
