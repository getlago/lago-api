# frozen_string_literal: true

module X402
  module CreditPurchases
    class ValidateService < BaseService
      Result = BaseResult

      def initialize(connection:, params:, verified_payment: nil)
        @connection = connection
        @params = params
        @verified_payment = verified_payment

        super
      end

      def call
        return result.validation_failure!(errors: input_errors) if input_errors.any?

        if plan_exists?
          result
        else
          result.not_found_failure!(resource: "plan")
        end
      end

      private

      attr_reader :connection, :params, :verified_payment

      delegate :organization, to: :connection, private: true

      def input_errors
        @input_errors ||= {
          plan_code: mandatory(:plan_code),
          wallet_code: mandatory(:wallet_code)
        }.compact
      end

      def mandatory(field)
        ["value_is_mandatory"] if params[field].blank?
      end

      def plan_exists?
        organization.plans.parents.exists?(code: params[:plan_code])
      end
    end
  end
end
