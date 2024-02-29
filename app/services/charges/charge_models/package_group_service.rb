# frozen_string_literal: true

module Charges
  module ChargeModels
    class PackageGroupService < Charges::ChargeModels::BaseService
      protected

      delegate :billable_metric_id, to: :charge
      
      def compute_amount
        return 0 if paid_units.negative?

        if !usage_charge_group&.available_group_usage.present?
          reset_available_group_usage
          group_count = initial_group_units
          usage_charge_group.update(current_package_count: group_count)

          return package_amount(group_count)
        end

        if added_group_units > 0
          next_available_package_usage = per_package_size - (paid_units % per_package_size)
          group_count = usage_charge_group.current_package_count + added_group_units
          reset_available_group_usage(next_available_package_usage)
          usage_charge_group.update(current_package_count: group_count)
        end
        
        package_amount(added_group_units)
      end

      def package_amount(count)
        count * per_group_package_unit_amount
      end

      # TODO: check on this
      def unit_amount
        return 0 if added_group_units <= 0

        compute_amount / added_group_units
      end

      # TODO: include group details here
      def amount_details
        if units.zero?
          return { free_units: '0.0', paid_units: '0.0', per_package_size: 0, per_package_unit_amount: '0.0' }
        end

        if paid_units.negative?
          return {
            free_units: BigDecimal(free_units).to_s,
            paid_units: '0.0',
            per_package_size:,
            per_package_unit_amount:,
          }
        end

        {
          free_units: BigDecimal(free_units).to_s,
          paid_units: BigDecimal(paid_units).to_s,
          per_package_size:,
          per_package_unit_amount:,
        }
      end

      def usage_charge_group
        @usage_charge_group ||= UsageChargeGroup.find_by(subscription_id: aggregation_result.subscription_id, charge_group_id: charge.charge_group_id)
      end

      def initial_group_units
        # Check how many packages (groups of units) are consumed
        # For the first time, it's rounded up, because a group counts from its first unit
        paid_units.fdiv(per_package_size).ceil
      end

      def group_usage
        paid_units.fdiv(current_package_available_usage)
      end

      def added_group_units
        # If group usage is exactly 1, no new group package should be counted
        @added_group_units ||= (group_usage > 1) ? group_usage.floor : 0
      end

      def per_group_package_unit_amount
        @per_group_package_unit_amount ||= BigDecimal(usage_charge_group.properties['amount'])
      end

      def paid_units
        @paid_units ||= units - free_units
      end

      def free_units
        @free_units ||= properties['free_units'] || 0
      end

      def per_package_size
        @per_package_size ||= properties['package_size']
      end
      
      def per_package_unit_amount
        @per_package_unit_amount ||= BigDecimal(properties['amount'])
      end

      def current_package_available_usage
        @current_package_available_usage ||= BigDecimal(usage_charge_group.available_group_usage[billable_metric_id])
      end

      def reset_available_group_usage(amount = nil)
        available_group_usage = {}
        usage_charge_group.charge_group.charges.each do |child_charge|
          available_group_usage[child_charge.billable_metric_id] = child_charge.properties['package_size']
        end
        # Update current package's available usage if amount is provided
        available_group_usage[billable_metric_id] = amount if amount.present?

        usage_charge_group.update(available_group_usage:)
      end
    end
  end
end
