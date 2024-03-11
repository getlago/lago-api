# frozen_string_literal: true

module Charges
  module ChargeModels
    class PackageTimebasedGroupService < Charges::ChargeModels::BaseService
      protected

      def compute_amount
        return @compute_amount if defined?(@compute_amount)
        return 0 if paid_units.negative?

        if usage_charge_group&.available_group_usage.blank?
          reset_available_group_usage
          group_count = initial_group_units
          usage_charge_group.update(current_package_count: group_count)

          return @compute_amount = package_amount(group_count)
        end

        if added_group_units.positive?
          group_count = usage_charge_group.current_package_count + added_group_units
          reset_available_group_usage(next_available_package_usage)
          usage_charge_group.update(current_package_count: group_count)

          add_timebased_event
        end

        @compute_amount = package_amount(added_group_units)
      end

      def next_available_package_usage
        return per_package_size - (paid_units % per_package_size) if paid_units > per_package_size

        per_package_size
      end

      def package_amount(count)
        count * per_group_package_unit_amount
      end

      def per_group_package_unit_amount
        @per_group_package_unit_amount ||= BigDecimal(charge_group.properties['amount'])
      end

      def initial_group_units
        # Check how many packages (groups of units) are consumed
        # For the first time, it's rounded up, because a group counts from its first unit
        paid_units.fdiv(per_package_size).ceil
      end

      def group_usage
        paid_units.fdiv(current_package_available_usage)
      end

      def current_package_available_usage
        @current_package_available_usage ||=
          BigDecimal(
            usage_charge_group
              .available_group_usage[charge.billable_metric_id],
          )
      end

      # TODO: check on this
      def unit_amount
        nil
      end

      def added_group_units
        @added_group_units ||= (group_usage > 1) ? group_usage.floor : 0
      end

      def reset_available_group_usage(init_pacakge_size = nil)
        available_group_usage = {}

        usage_charge_group.charge_group.charges.package_group.each do |child_charge|
          available_group_usage[child_charge.billable_metric_id] = child_charge.properties['package_size']
        end
        # Update current package's available usage if amount is provided
        available_group_usage[charge.billable_metric_id] = init_pacakge_size if init_pacakge_size.present?

        usage_charge_group.update(available_group_usage:)
      end

      def usage_charge_group
        @usage_charge_group ||= UsageChargeGroup.where(
          subscription_id: aggregation_result.subscription_id,
          charge_group_id: charge.charge_group_id,
        ).last
      end

      def per_package_size
        @per_package_size ||= properties['package_size']
      end

      def paid_units
        @paid_units ||= units - free_units
      end

      def free_units
        @free_units ||= properties['free_units'] || 0
      end

      def add_timebased_event
        TimebasedEvent.create!(
          organization: event.organization,
          external_customer_id: event.external_customer_id,
          external_subscription_id: event.external_subscription_id,
          metadata: event.metadata,
          timestamp: Time.zone.at(event.timestamp),
        )
      end

      def charge_group
        @charge_group ||= ChargeGroup.find(charge.charge_group_id)
      end

      def event
        @event ||= aggregation_result.event
      end
    end
  end
end
