# frozen_string_literal: true

module PlanWallets
  class CreateService < BaseService
    Result = BaseResult[:plan_wallet]

    ATTRIBUTES = %i[
      code name invoice_display_name currency tax_application priority top_up_min_amount_cents top_up_max_amount_cents
    ].freeze

    activity_loggable(
      action: "plan_wallet.created",
      record: -> { result.plan_wallet }
    )

    def initialize(catalog_plan:, params:)
      @catalog_plan = catalog_plan
      @params = params.to_h.with_indifferent_access
      super
    end

    def call
      return result.not_found_failure!(resource: "plan") unless catalog_plan

      # Credit is counted in the wallet currency, never derived from the price paid.
      if params.key?(:rate_amount)
        return result.single_validation_failure!(field: :rate_amount, error_code: "not_supported")
      end

      if (field = malformed_param)
        return result.single_validation_failure!(field:, error_code: "value_is_invalid")
      end

      unless params[:tax_application].nil? || PlanWallet.tax_applications.key?(params[:tax_application])
        return result.single_validation_failure!(
          field: :tax_application,
          error_code: "value_is_invalid",
          meta: {allowed_values: PlanWallet.tax_applications.keys}
        )
      end

      ActiveRecord::Base.transaction do
        plan_wallet = catalog_plan.wallets.create!(organization:, **params.slice(*ATTRIBUTES).compact.symbolize_keys)

        replace_metadata!(plan_wallet) unless params[:metadata].nil?
        CatalogWallets::ApplyTaxesService.call!(wallet: plan_wallet, tax_codes: params[:tax_codes]) unless params[:tax_codes].nil?
        CatalogWalletSelectors::ReplaceService.call!(wallet: plan_wallet, applies_to: params[:applies_to]) unless params[:applies_to].nil?

        result.plan_wallet = plan_wallet
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue ActiveRecord::RecordNotUnique => e
      unique_index_failure!(e, "index_plan_wallets_on_catalog_plan_id_and_code" => :code)
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e.result.error)
    end

    private

    attr_reader :catalog_plan, :params

    delegate :organization, to: :catalog_plan

    # The metadata record names its errors in sentences, on its own `value` column.
    def replace_metadata!(plan_wallet)
      unless Metadata::UpdateItemService.call(owner: plan_wallet, value: params[:metadata]).success?
        result.single_validation_failure!(field: :metadata, error_code: "value_is_invalid").raise_if_error!
      end
    end

    # The field whose value has another shape than its service reads: a metadata object, a list of tax codes.
    def malformed_param
      if !params[:metadata].nil? && !params[:metadata].is_a?(Hash)
        :metadata
      elsif !params[:tax_codes].nil? && !(params[:tax_codes].is_a?(Array) && params[:tax_codes].all?(String))
        :tax_codes
      end
    end
  end
end
