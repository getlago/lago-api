# frozen_string_literal: true

module PlanWallets
  class CreateService < BaseService
    include CatalogWallets::SettingsParams

    Result = BaseResult[:plan_wallet]

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

      if (field = malformed_param)
        return result.single_validation_failure!(field:, error_code: "value_is_invalid")
      end

      return unknown_tax_application_failure unless params[:tax_application].nil? || known_tax_application?

      ActiveRecord::Base.transaction do
        plan_wallet = catalog_plan.wallets.create!(organization:, **params.slice(*ATTRIBUTES).compact.symbolize_keys)

        replace_metadata!(plan_wallet, params[:metadata]) unless params[:metadata].nil?
        replace_taxes_and_scope!(plan_wallet)

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
  end
end
