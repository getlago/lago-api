# frozen_string_literal: true

module Charges
  class UpdateChildrenService < BaseService
    Result = BaseResult

    def initialize(params:, old_parent_attrs:, old_parent_filters_attrs:, old_parent_applied_pricing_unit_attrs:)
      @params = params
      @old_parent_attrs = old_parent_attrs
      @old_parent_filters_attrs = old_parent_filters_attrs
      @old_parent_applied_pricing_unit_attrs = old_parent_applied_pricing_unit_attrs

      super
    end

    def call
      return result unless charge

      Charge.with_advisory_lock!("update_children_charge_#{charge.id}", timeout_seconds: 0) do
        Charge.no_touching do
          Plan.no_touching do
            charge.children
              .joins(plan: :subscriptions)
              .where(subscriptions: {status: %w[active pending]})
              .distinct
              .find_each do |child_charge|
                Charges::UpdateService.call!(
                  charge: child_charge,
                  params:,
                  cascade_options: {
                    cascade: true,
                    parent_filters: old_parent_filters_attrs,
                    equal_properties: old_parent.equal_properties?(child_charge),
                    equal_applied_pricing_unit_rate: old_parent.equal_applied_pricing_unit_rate?(child_charge)
                  }
                )
              end
          end
        end
      end

      result
    end

    private

    attr_reader :params, :old_parent_attrs, :old_parent_filters_attrs, :old_parent_applied_pricing_unit_attrs

    def charge
      @charge ||= Charge.find_by(id: old_parent_attrs["id"])
    end

    def old_parent
      @old_parent ||= begin
        parent = Charge.new(old_parent_attrs)
        if old_parent_applied_pricing_unit_attrs.present?
          parent.build_applied_pricing_unit(old_parent_applied_pricing_unit_attrs)
        end
        parent
      end
    end
  end
end
