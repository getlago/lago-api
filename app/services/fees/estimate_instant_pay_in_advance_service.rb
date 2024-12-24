# frozen_string_literal: true

module Fees
  class EstimateInstantPayInAdvanceService < BaseService
    def initialize(organization:, params:)
      @organization = organization
      # NOTE: validation is shared with event creation and is expecting a transaction_id
      @params = params.merge(transaction_id: SecureRandom.uuid)

      super
    end

    def call
      validation_result = Events::ValidateCreationService.call(organization:, params:, customer:, subscriptions:)
    end
  end
end
