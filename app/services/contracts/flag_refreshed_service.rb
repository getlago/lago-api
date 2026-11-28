# frozen_string_literal: true

module Contracts
  class FlagRefreshedService < BaseService
    Result = BaseResult

    def initialize(organization_id:, external_contract_id:)
      @organization_id = organization_id
      @external_contract_id = external_contract_id
      super
    end

    def call
      return result unless organization&.product_catalog_enabled?
      return result unless organization.feature_flag_enabled?(:contract_alerts)

      contract = organization.contracts.active.find_by(external_id: external_contract_id)
      UsageMonitoring::TrackContractActivityService.call!(contract:) if contract

      result
    end

    private

    attr_reader :organization_id, :external_contract_id

    def organization
      @organization ||= Organization.find_by(id: organization_id)
    end
  end
end
