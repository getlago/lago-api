# frozen_string_literal: true

module PlanWallets
  # Edits a plan's wallet template. Contracts hold their own copy, so an edit reaches new contracts only.
  class UpdateService < BaseService
    Result = BaseResult[:plan_wallet]

    ATTRIBUTES = CreateService::ATTRIBUTES
    RELATED_PARAMS = %i[metadata tax_codes applies_to].freeze

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
      return result.not_found_failure!(resource: "wallet") unless plan_wallet

      if params.key?(:rate_amount)
        return result.single_validation_failure!(field: :rate_amount, error_code: "not_supported")
      end

      if params.key?(:tax_application) && !PlanWallet.tax_applications.key?(params[:tax_application])
        return result.single_validation_failure!(
          field: :tax_application,
          error_code: "value_is_invalid",
          meta: {allowed_values: PlanWallet.tax_applications.keys}
        )
      end

      plan_wallet.with_lock do
        return result.not_found_failure!(resource: "wallet") if plan_wallet.discarded?

        # Contracts find their wallet by the template's code, so it freezes with the first contract.
        if code_change_requested? && catalog_plan.attached_to_contracts?
          return result.single_validation_failure!(field: :code, error_code: "plan_locked")
        end

        if params[:currency].present? && params[:currency] != catalog_plan.currency
          return result.single_validation_failure!(field: :currency, error_code: "currency_does_not_match")
        end

        plan_wallet.assign_attributes(params.slice(*ATTRIBUTES))
        # Taxes, scope and metadata are part of the template's body, so their edit dates it too.
        plan_wallet.updated_at = Time.current if RELATED_PARAMS.any? { params.key?(it) }
        plan_wallet.save!

        Metadata::UpdateItemService.call!(owner: plan_wallet, value: params[:metadata]) if params.key?(:metadata)
        CatalogWallets::ApplyTaxesService.call!(wallet: plan_wallet, tax_codes: params[:tax_codes]) unless params[:tax_codes].nil?
        CatalogWalletSelectors::ReplaceService.call!(wallet: plan_wallet, applies_to: params[:applies_to]) unless params[:applies_to].nil?
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
