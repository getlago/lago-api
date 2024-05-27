# frozen_string_literal: true

module Wallets
  module RecurringTransactionRules
    class ValidateService < BaseService
      def initialize(params:)
        @params = params
        super
      end

      def call
        return true if valid_interval?
        return true if valid_threshold?

        false
      end

      private

      attr_reader :params

      def trigger
        @trigger ||= params[:trigger]&.to_s
      end

      def valid_interval?
        trigger == "interval" && RecurringTransactionRule.intervals.key?(params[:interval])
      end

      def valid_threshold?
        trigger == "threshold" && ::Validators::DecimalAmountService.new(params[:threshold_credits]).valid_decimal?
      end
    end
  end
end
