# frozen_string_literal: true

module UsageThresholds
  class OverrideService < BaseService
    def initialize(threshold:, params:)
      @threshold = threshold
      @params = params

      super
    end

    def call
      ActiveRecord::Base.transaction do
        new_threshold = threshold.dup.tap do |c|
          c.amount_cents = params[:amount_cents] if params.key?(:amount_cents)
          c.recurring = params[:recurring] if params.key?(:recurring)
          c.threshold_display_name = params[:threshold_display_name] if params.key?(:threshold_display_name)
          c.plan_id = params[:plan_id]
        end
        new_threshold.save!

        result.usage_threshold = new_threshold
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :threshold, :params
  end
end
