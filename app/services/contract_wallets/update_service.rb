# frozen_string_literal: true

module ContractWallets
  class UpdateService < BaseService
    include CatalogWallets::SettingsParams

    Result = BaseResult[:contract_wallet]

    # The code addresses the wallet, and its credit was bought in its currency under its tax mode.
    IMMUTABLE_ATTRIBUTES = %i[code currency tax_application].freeze

    activity_loggable(
      action: "contract_wallet.updated",
      record: -> { contract_wallet }
    )

    def initialize(contract_wallet:, params:)
      @contract_wallet = contract_wallet
      @params = params.to_h.with_indifferent_access
      super
    end

    def call
      return result.not_found_failure!(resource: "contract_wallet") unless contract_wallet

      if (field = malformed_param)
        return result.single_validation_failure!(field:, error_code: "value_is_invalid")
      end

      if (field = changed_immutable_attribute)
        return result.single_validation_failure!(field:, error_code: "value_cannot_be_changed")
      end

      # Locked so the status check holds: the clock may end the contract meanwhile.
      # Unlike FOR UPDATE, it lets rows that reference the contract be inserted meanwhile.
      contract.with_lock("FOR NO KEY UPDATE") do
        return result.forbidden_failure!(code: "contract_not_live") unless Contract::LIVE_STATUSES.include?(contract.status)

        contract_wallet.lock!
        return result.not_found_failure!(resource: "contract_wallet") if contract_wallet.discarded?

        contract_wallet.assign_attributes(params.slice(*(ATTRIBUTES - IMMUTABLE_ATTRIBUTES)))
        # Taxes, scope and metadata are part of the wallet's body, so their edit dates it too.
        contract_wallet.updated_at = Time.current if RELATED_PARAMS.any? { params.key?(it) }
        contract_wallet.save!

        replace_metadata!(contract_wallet, params[:metadata]) if params.key?(:metadata)
        replace_taxes_and_scope!(contract_wallet)
      end

      result.contract_wallet = contract_wallet
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e.result.error)
    end

    private

    attr_reader :contract_wallet, :params

    delegate :contract, to: :contract_wallet

    # A request may repeat what it read: only another value is refused.
    def changed_immutable_attribute
      IMMUTABLE_ATTRIBUTES.find { params.key?(it) && params[it] != contract_wallet[it] }
    end
  end
end
