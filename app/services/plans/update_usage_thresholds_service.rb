# frozen_string_literal: true

module Plans
  class UpdateUsageThresholdsService < BaseService
    Result = BaseResult[:plan, :partial]

    def initialize(plan:, usage_thresholds_params:, partial:)
      @plan = plan
      @usage_thresholds_params = sanitize_params(usage_thresholds_params)
      @partial = partial
      super
    end

    def call
      result.plan = plan
      result.partial = partial

      return result unless plan.organization.progressive_billing_enabled?
      return result if plan.child?

      return result if usage_thresholds_params.empty? && partial?

      # TODO: Move this to validation service
      return result.single_validation_failure!(error_code: "missing_amount_cents", field: :usage_thresholds) if missing_amount_cents?
      return result.single_validation_failure!(error_code: "duplicated_values", field: :usage_thresholds) if duplicated_amount_cents?
      return result.single_validation_failure!(error_code: "multiple_recurring_thresholds", field: :usage_thresholds) if multiple_recurring_thresholds?

      ActiveRecord::Base.transaction do
        delete_all_thresholds if full?

        update_recurring_threshold
        update_or_create_thresholds
      end

      plan.usage_thresholds.reload
      LifetimeUsages::FlagRefreshFromPlanUpdateJob.perform_after_commit(plan) if plan.usage_thresholds.size > 0

      result
    end

    private

    attr_reader :plan, :usage_thresholds_params, :partial
    alias_method :partial?, :partial

    def full?
      !partial
    end

    def sanitize_params(usage_thresholds_params)
      usage_thresholds_params.map do |p|
        h = p.to_h.deep_symbolize_keys.slice(:threshold_display_name, :amount_cents, :recurring)
        h[:recurring] ||= false
        h
      end
    end

    def missing_amount_cents?
      usage_thresholds_params.any? { |p| p[:amount_cents].blank? }
    end

    def duplicated_amount_cents?
      grouped = usage_thresholds_params.group_by { |p| [p[:amount_cents], p[:recurring]] }
      grouped.any? { |_, v| v.size > 1 }
    end

    def multiple_recurring_thresholds?
      usage_thresholds_params.count { |p| p[:recurring] } > 1
    end

    def delete_all_thresholds
      plan.usage_thresholds.update_all(deleted_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    end

    def update_recurring_threshold
      recurring_params = usage_thresholds_params.find { |p| p[:recurring] }
      return unless recurring_params

      existing_threshold = plan.usage_thresholds.find { |t| t.recurring }

      if existing_threshold
        existing_threshold.update!(
          amount_cents: recurring_params[:amount_cents],
          threshold_display_name: recurring_params[:threshold_display_name]
        )
      else
        create_threshold(recurring_params, recurring: true)
      end
    end

    def update_or_create_thresholds
      usage_thresholds_params.reject { |p| p[:recurring] }.each do |threshold_params|
        existing_threshold = plan.usage_thresholds.find { |t| t.amount_cents == threshold_params[:amount_cents] && !t.recurring }

        if existing_threshold
          update_threshold(existing_threshold, threshold_params)
        else
          create_threshold(threshold_params)
        end
      end
    end

    def update_threshold(threshold, params)
      threshold.threshold_display_name = params[:threshold_display_name] if params.key?(:threshold_display_name)
      threshold.save!
    end

    def create_threshold(params, recurring: false)
      plan.usage_thresholds.create!(
        organization: plan.organization,
        threshold_display_name: params[:threshold_display_name],
        amount_cents: params[:amount_cents],
        recurring:
      )
    end
  end
end
