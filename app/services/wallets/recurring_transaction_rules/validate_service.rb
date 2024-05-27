# frozen_string_literal: true

module Wallets
  module RecurringTransactionRules
    class ValidateService < BaseService
      def initialize(params:)
        @params = params
        super
      end

      def call
        return false unless valid_trigger?
        return false unless valid_method?

        true
      end

      private

      attr_reader :params

      def trigger
        @trigger ||= params[:trigger]&.to_s
      end

      def method
        @method ||= params[:method]&.to_s
      end

      def valid_trigger?
        valid_interval_trigger? || valid_threshold_trigger?
      end

      def valid_interval_trigger?
        trigger == "interval" && RecurringTransactionRule.intervals.key?(params[:interval])
      end

      def valid_threshold_trigger?
        trigger == "threshold" && ::Validators::DecimalAmountService.new(params[:threshold_credits]).valid_decimal?
      end

      def valid_method?
        (method == "target") ? valid_target_method? : true
      end

      def valid_target_method?
        ::Validators::DecimalAmountService.new(params[:target_ongoing_balance]).valid_decimal?
      end
    end
  end
end
