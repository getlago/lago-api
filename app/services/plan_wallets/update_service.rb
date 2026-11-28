# frozen_string_literal: true

module PlanWallets
  # Edits a plan's wallet template. Contracts hold their own copy, so an edit reaches new contracts only.
  class UpdateService < BaseService
    include CatalogWallets::SettingsParams

    Result = BaseResult[:plan_wallet]

    activity_loggable(
      action: "plan_wallet.updated",
      record: -> { plan_wallet }
    )

    def initialize(plan_wallet:, params:)
      @plan_wallet = plan_wallet
      @params = params.to_h.with_indifferent_access
      super
    end

    def call
      return result.not_found_failure!(resource: "plan_wallet") unless plan_wallet

      if (field = malformed_param)
        return result.single_validation_failure!(field:, error_code: "value_is_invalid")
      end

      return unknown_tax_application_failure if params.key?(:tax_application) && !known_tax_application?

      plan_wallet.with_lock do
        return result.not_found_failure!(resource: "plan_wallet") if plan_wallet.discarded?

        # Each contract copies the template with its code. Freezing it with the first contract keeps one
        # code across the plan's contracts; a canceled contract keeps the code it was given.
        if code_change_requested? && catalog_plan.attached_to_contracts?
          return result.single_validation_failure!(field: :code, error_code: "plan_locked")
        end

        plan_wallet.assign_attributes(params.slice(*ATTRIBUTES))
        # Taxes, scope and metadata are part of the template's body, so their edit dates it too.
        plan_wallet.updated_at = Time.current if RELATED_PARAMS.any? { params.key?(it) }
        plan_wallet.save!

        replace_metadata!(plan_wallet) if params.key?(:metadata)
        replace_taxes_and_scope!(plan_wallet)
      end

      result.plan_wallet = plan_wallet
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue ActiveRecord::RecordNotUnique => e
      unique_index_failure!(e, "index_plan_wallets_on_catalog_plan_id_and_code" => :code)
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e.result.error)
    end

    private

    attr_reader :plan_wallet, :params

    delegate :catalog_plan, to: :plan_wallet

    def code_change_requested?
      params.key?(:code) && params[:code] != plan_wallet.code
    end
  end
end
