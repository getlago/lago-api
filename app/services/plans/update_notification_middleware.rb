# frozen_string_literal: true

module Plans
  class UpdateNotificationMiddleware < Middlewares::BaseMiddleware
    def before_call
      @snapshot = create_snapshot(initial_plan)
    end

    def after_call(result)
      return unless result.success?

      final_state = create_snapshot(result.plan)
      compare_and_notify(final_state)
    end

    private

    def initial_plan
      arg = kwargs[:plan]
      return unless arg

      service_instance.instance_exec(&arg)
    end

    def create_snapshot(plan)
      return [] unless plan

      ::CollectionSerializer.new(
        plan.charges.includes(:applied_pricing_unit),
        ::V1::ChargeSerializer,
        collection_name: "charges"
      ).serialize_models
    end

    def compare_and_notify(final_state)
      before = @snapshot.index_with { it[:lago_id] }
      after = final_state.index_with { it[:lago_id] }

      (before.keys - after.keys).each do |charge_id|
        notify_deleted_charge(charge_id)
      end

      (after.keys - before.keys).each do |charge_id|
        notify_created_charge(charge_id)
      end

      (before.keys & after.keys).each do |charge_id|
        compare_charge_filters_and_notify(before[charge_id], after[charge_id])
      end
    end

    def notify_deleted_charge(charge_id)
      # Implement notification logic here
    end

    def notify_created_charge(charge_id)
      # Implement notification logic here
    end

    def compare_charge_filters_and_notify(before, after)
      # Filters have changed, we need to reprocess all events
      if before[:filters].map { |it| it[:values] } != after[:filters].map { |it| it[:values] }
        notify_updated_charge_filter(before[:lago_id])
        return
      end

      # Pricing group keys have changed, we need to reprocess all events for the charge without filter
      if before[:properties][:pricing_group_keys] != after[:properties][:pricing_group_keys]
        notify_updated_pricing_group_keys(before[:lago_id], "charge")
      end

      filters_after = after[:filters].index_with { it[:lago_id] }
      before[:filters].each do |filter|
        filter_after = filters_after[filter[:lago_id]]

        # Filter's pricing group keys have changed, we need to reprocess all events for the filter
        if filter[:properties][:pricing_group_keys] != filter_after[:properties][:pricing_group_keys]
          notify_updated_pricing_group_keys(filter[:lago_id], "charge_filter")
        end
      end
    end

    def notify_updated_charge(charge_id)
      # Implement notification logic here
    end

    def notify_updated_pricing_group_keys(record_id, record_type)
      # Implement notification logic here
    end
  end
end
