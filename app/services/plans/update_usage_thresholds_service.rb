# frozen_string_literal: true

module Plans
  class UpdateUsageThresholdsService < BaseService
    Result = BaseResult[:plan]

    def initialize(plan:, usage_thresholds_params:)
      @plan = plan
      @usage_thresholds_params = usage_thresholds_params
      super
    end

    def call
      result.plan = plan
      return result unless plan.organization.progressive_billing_enabled?

      if usage_thresholds_params.empty?
        plan.usage_thresholds.discard_all
      else
        process_usage_thresholds
        LifetimeUsages::FlagRefreshFromPlanUpdateJob.perform_later(plan)
      end

      result
    end

    private

    def process_usage_thresholds
      created_thresholds_ids = []

      hash_thresholds = usage_thresholds_params.map { |c| c.to_h.deep_symbolize_keys }
      hash_thresholds.each do |payload_threshold|
        usage_threshold = plan.usage_thresholds.find_by(id: payload_threshold[:id])

        if usage_threshold
          if payload_threshold.key?(:threshold_display_name)
            usage_threshold.threshold_display_name = payload_threshold[:threshold_display_name]
          end

          if payload_threshold.key?(:amount_cents)
            usage_threshold.amount_cents = payload_threshold[:amount_cents]
          end

          if payload_threshold.key?(:recurring)
            usage_threshold.recurring = payload_threshold[:recurring]
          end

          # This means that in the UI we just removed an existing threshold
          # and then just re-added a threshold (which no longer has an id) with the same amount
          # so we discard the existing one and we're inserting a new one instead
          if !usage_threshold.valid? && usage_threshold.errors.where(:amount_cents, :taken).present?
            usage_threshold.discard!
          else
            usage_threshold.save!
            next
          end
        end

        created_threshold = create_usage_threshold(plan.reload, payload_threshold)
        created_thresholds_ids.push(created_threshold.id)
      end
      # NOTE: Delete thresholds that are no more linked to the plan
      sanitize_thresholds(plan, hash_thresholds, created_thresholds_ids)
    end

    def sanitize_thresholds(plan, args_thresholds, created_thresholds_ids)
      args_thresholds_ids = args_thresholds.map { |c| c[:id] }.compact
      thresholds_ids = plan.usage_thresholds.pluck(:id) - args_thresholds_ids - created_thresholds_ids
      plan.usage_thresholds.where(id: thresholds_ids).discard_all
    end

    def create_usage_threshold(plan, params)
      usage_threshold = plan.usage_thresholds.find_or_initialize_by(
        recurring: params[:recurring] || false,
        amount_cents: params[:amount_cents]
      )

      existing_recurring_threshold = plan.usage_thresholds.recurring.first

      if params[:recurring] && existing_recurring_threshold
        usage_threshold = existing_recurring_threshold
      end

      usage_threshold.threshold_display_name = params[:threshold_display_name]
      usage_threshold.amount_cents = params[:amount_cents]
      usage_threshold.organization_id = plan.organization_id

      usage_threshold.save!
      usage_threshold
    end

    attr_reader :plan, :usage_thresholds_params
  end
end
