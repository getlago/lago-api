# frozen_string_literal: true

module UsageMonitoring
  class TrackContractActivityService < BaseService
    Result = BaseResult

    def initialize(contract:)
      @contract = contract
      super
    end

    def call
      return result unless License.premium?
      return result unless contract.organization.feature_flag_enabled?(:contract_alerts)
      return result unless contract.active?
      return result unless contract.contract_alerts.exists?

      ContractActivity.insert_all( # rubocop:disable Rails/SkipsModelValidations
        [{organization_id: contract.organization_id, contract_id: contract.id}],
        unique_by: :idx_contract_activity_unique
      )

      result
    end

    private

    attr_reader :contract
  end
end
