# frozen_string_literal: true

module Api
  module V2
    module ContractLookup
      extend ActiveSupport::Concern

      class ContractCodeError < StandardError; end

      included do
        rescue_from ContractCodeError do |error|
          validation_errors(errors: {contract_code: [error.message]})
        end
      end

      private

      def find_contract(external_id)
        contracts = current_organization.contracts.where(external_id:)

        if params.key?(:contract_code)
          code = params[:contract_code]
          unless code.is_a?(String) && code.present?
            raise ContractCodeError, "value_is_invalid"
          end

          contracts.find_by(code:)
        else
          matches = contracts.limit(2).to_a
          if matches.many?
            raise ContractCodeError, "value_is_mandatory"
          end

          matches.first
        end
      end
    end
  end
end
