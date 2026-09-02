# frozen_string_literal: true

module Contracts
  # Records a new agreement. The plan is optional by design: a plan-less
  # contract prices through directly attached rate cards. The contract is
  # active when its start has arrived, pending when it starts in the future
  # — lifecycle state lives in the status, the dates only carry the window.
  class CreateService < BaseService
    Result = BaseResult[:contract]

    def initialize(organization:, params:)
      @organization = organization
      @params = params.to_h.with_indifferent_access
      super
    end

    def call
      return result.not_found_failure!(resource: "customer") unless customer

      if params[:plan_code].present? && plan.nil?
        return result.not_found_failure!(resource: "plan")
      end

      if plan && !plan.product_catalog?
        return result.single_validation_failure!(field: :plan, error_code: "not_a_product_catalog_plan")
      end

      # Date columns: a malformed value would silently cast to nil instead of
      # failing, so formats are rejected explicitly.
      %i[billing_anchor_date started_at ended_at].each do |field|
        if params[field].present? && !Utils::Datetime.valid_format?(params[field])
          return result.single_validation_failure!(field:, error_code: "value_is_invalid")
        end
      end

      # A window that already closed cannot be created: nothing would ever
      # terminate it, leaving a zombie active contract.
      if params[:ended_at].present? && Time.zone.parse(params[:ended_at].to_s) <= Time.current
        return result.single_validation_failure!(field: :ended_at, error_code: "already_ended")
      end

      # One live agreement per external id. Replacement flows (upgrade,
      # downgrade, renewal) will create their pending sibling explicitly when
      # they exist; a blind second create is a mistake, not a replacement.
      # Advisory under concurrency — the partial unique index closes the race.
      if organization.contracts.where(status: %w[pending active], external_id: params[:external_id]).exists?
        return result.single_validation_failure!(field: :external_id, error_code: "value_already_exists")
      end

      started_at = params[:started_at].present? ? Time.zone.parse(params[:started_at].to_s) : Time.current

      ActiveRecord::Base.transaction do
        contract = organization.contracts.create!(
          customer:,
          plan:,
          external_id: params[:external_id],
          name: params[:name],
          billing_time: params[:billing_time].presence || "calendar",
          billing_anchor_date: params[:billing_anchor_date],
          started_at:,
          ended_at: params[:ended_at],
          status: started_at.future? ? :pending : :active
        )

        Contracts::MaterializeRateCardsService.call!(contract:) if contract.plan

        result.contract = contract
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue ActiveRecord::RecordNotUnique => e
      # A concurrent create won the race past the advisory check; same answer
      # as the check itself. Any other uniqueness violation in the transaction
      # stays loud instead of masquerading as a duplicate external id.
      raise unless e.message.include?("index_contracts_on_live_external_id")

      result.single_validation_failure!(field: :external_id, error_code: "value_already_exists")
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :organization, :params

    def customer
      @customer ||= organization.customers.find_by(external_id: params[:external_customer_id])
    end

    def plan
      @plan ||= organization.plans.parents.find_by(code: params[:plan_code])
    end
  end
end
