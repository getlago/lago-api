# frozen_string_literal: true

module Plans
  class UpdateNotificationMiddleware < Middlewares::BaseMiddleware
    def before_call
      return unless should_notify?

      @snapshot = create_snapshot(initial_plan)
    end

    def after_call(result)
      return unless should_notify?
      return unless result.success?

      @plan = result.plan

      final_state = create_snapshot(@plan)
      compare_and_notify(final_state)
    rescue => e
      # Avoid raising error from the middleware and blocking the update process
      if defined?(Sentry)
        Sentry.capture_exception(e)
      else
        Rails.logger.error("Error in Plans::UpdateNotificationMiddleware: #{e.message}")
      end
    end

    private

    def initial_plan
      arg = kwargs[:plan]
      return unless arg

      service_instance.instance_exec(&arg)
    end

    def should_notify?
      return false if ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"].blank?
      return false if ENV["LAGO_KAFKA_PLAN_CONFIG_UPDATED_TOPIC"].blank?

      initial_plan&.organization&.clickhouse_live_aggregation_enabled?
    end

    def create_snapshot(plan)
      return [] unless plan

      plan.charges.map do |charge|
        {
          id: charge.id,
          pricing_group_keys: charge.pricing_group_keys,
          filters: charge.filters.map { |f| {id: f.id, pricing_group_keys: f.pricing_group_keys, values: f.to_h} }
        }
      end
    end

    def compare_and_notify(final_state)
      before = @snapshot.index_by { it[:id] }
      after = final_state.index_by { it[:id] }

      deleted_ids = (before.keys - after.keys)
      notify_deleted_charge(deleted_ids) if deleted_ids.present?

      created_ids = (after.keys - before.keys)
      notify_created_charge(created_ids) if created_ids.present?

      (before.keys & after.keys).each do |charge_id|
        compare_charge_filters_and_notify(before[charge_id], after[charge_id])
      end
    end

    def notify_deleted_charge(charge_ids)
      Plans::UpdatedKafkaProducerService.call!(
        plan: @plan,
        resources_type: "charge",
        resources_ids: charge_ids,
        event_type: "charges.deleted",
        timestamp: @plan.updated_at
      )
    end

    def notify_created_charge(charge_ids)
      Plans::UpdatedKafkaProducerService.call!(
        plan: @plan,
        resources_type: "charge",
        resources_ids: charge_ids,
        event_type: "charges.created",
        timestamp: @plan.updated_at
      )
    end

    def compare_charge_filters_and_notify(before, after)
      # Filters have changed, we need to reprocess all events
      before_values = before[:filters].map { |it| {id: it[:id], values: it[:values]} }
      after_values = after[:filters].map { |it| {id: it[:id], values: it[:values]} }

      if before_values != after_values
        notify_updated_charge(before[:id])
        return
      end

      # Charge's ricing group keys have changed, we need to reprocess all events for the charge without filter
      if before[:pricing_group_keys] != after[:pricing_group_keys]
        notify_updated_pricing_group_keys([before[:id]], "charge")
      end

      filters_after = after[:filters].index_by { it[:id] }
      updated = before[:filters].select do |filter|
        filter_after = filters_after[filter[:id]]

        # Filter's pricing group keys have changed, we need to reprocess all events for the filter
        filter[:pricing_group_keys] != filter_after[:pricing_group_keys]
      end
      notify_updated_pricing_group_keys(updated.map { |it| it[:id] }, "charge_filter") if updated.any?
    end

    def notify_updated_charge(charge_id)
      Plans::UpdatedKafkaProducerService.call!(
        plan: @plan,
        resources_type: "charge",
        resources_ids: [charge_id],
        event_type: "charges.updated",
        timestamp: @plan.updated_at
      )
    end

    def notify_updated_pricing_group_keys(record_ids, record_type)
      Plans::UpdatedKafkaProducerService.call!(
        plan: @plan,
        resources_type: record_type,
        resources_ids: record_ids,
        event_type: "#{record_type}s.pricing_group_keys_updated",
        timestamp: @plan.updated_at
      )
    end
  end
end
