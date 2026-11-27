# frozen_string_literal: true

module ContractWallets
  class CreateService < BaseService
    include CatalogWallets::SettingsParams

    Result = BaseResult[:contract_wallet]

    activity_loggable(
      action: "contract_wallet.created",
      record: -> { result.contract_wallet }
    )

    def initialize(contract:, params:)
      @contract = contract
      @params = params.to_h.with_indifferent_access
      super
    end

    def call
      return result.not_found_failure!(resource: "contract") unless contract

      if (field = malformed_param)
        return result.single_validation_failure!(field:, error_code: "value_is_invalid")
      end

      return unknown_tax_application_failure unless params[:tax_application].nil? || known_tax_application?

      # Locked so the status check holds: the clock may end the contract meanwhile.
      # Unlike FOR UPDATE, it lets rows that reference the contract be inserted meanwhile.
      contract.with_lock("FOR NO KEY UPDATE") do
        return result.forbidden_failure!(code: "contract_not_live") unless Contract::LIVE_STATUSES.include?(contract.status)

        contract_wallet = contract.wallets.create!(
          organization:,
          customer: contract.customer,
          **params.slice(*ATTRIBUTES).compact.symbolize_keys
        )

        replace_metadata!(contract_wallet, params[:metadata]) unless params[:metadata].nil?
        replace_taxes_and_scope!(contract_wallet)

        result.contract_wallet = contract_wallet
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue ActiveRecord::RecordNotUnique => e
      unique_index_failure!(e, "index_catalog_wallets_on_contract_id_and_code" => :code)
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e.result.error)
    end

    private

    attr_reader :contract, :params

    delegate :organization, to: :contract
  end
end
