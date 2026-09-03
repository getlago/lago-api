# frozen_string_literal: true

module ContractRateCards
  # Edits a contract's rate card entry. While the contract is pending the
  # entry is freely editable (authoring window). Once the contract is active
  # its cards are signed; unit versioning on an active contract is a lifecycle
  # concern priced by the billing engine, not an authoring edit here.
  class UpdateService < BaseService
    Result = BaseResult[:contract_rate_card]

    def initialize(contract_rate_card:, params:)
      @contract_rate_card = contract_rate_card
      @params = params.to_h.with_indifferent_access
      super
    end

    def call
      return result.not_found_failure!(resource: "applied_rate_card") unless contract_rate_card

      if contract_rate_card.contract.locked?
        return result.single_validation_failure!(field: :contract, error_code: "contract_locked")
      end

      # The column is a date and NOT NULL: a malformed or explicit-null value
      # would cast to nil and crash on save instead of failing cleanly.
      if params.key?(:billing_anchor_date) && !Utils::Datetime.valid_format?(params[:billing_anchor_date].to_s)
        return result.single_validation_failure!(field: :billing_anchor_date, error_code: "value_is_invalid")
      end

      contract_rate_card.units = params[:units] if params.key?(:units)
      contract_rate_card.billing_anchor_date = params[:billing_anchor_date] if params.key?(:billing_anchor_date)
      contract_rate_card.save!

      result.contract_rate_card = contract_rate_card
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :contract_rate_card, :params
  end
end
