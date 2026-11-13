# frozen_string_literal: true

module Charges
  class UpdateChildrenService < BaseService
    Result = BaseResult[:charge]

    LOCK_TIMEOUT_SECONDS = 5

    def initialize(charge:, params:, old_parent_attrs:, old_parent_applied_pricing_unit_attrs:, child_ids:)
      @charge = charge
      @params = params
      @old_parent = Charge.new(old_parent_attrs)
      @child_ids = child_ids

      if old_parent_applied_pricing_unit_attrs.present?
        @old_parent.build_applied_pricing_unit(old_parent_applied_pricing_unit_attrs)
      end

      super
    end

    def call
      return result unless charge

      # skip touching to avoid deadlocks and redundant cascading updates
      Charge.no_touching do
        Plan.no_touching do
          charge.children.where(id: child_ids).find_each do |child_charge|
            update_child(child_charge)
          end
        end
      end

      result.charge = charge
      result
    end

    private

    attr_reader :charge, :params, :old_parent, :child_ids

    # Locked per child rather than per parent: the batches of one cascade hold disjoint children and run
    # in parallel, while two cascades of the same parent still never update the same child concurrently.
    def update_child(child_charge)
      Charge.transaction do
        Charge.with_advisory_lock!(
          "cascade_update_charge_#{child_charge.id}",
          transaction: true,
          timeout_seconds: LOCK_TIMEOUT_SECONDS
        ) do
          # Another cascade may have updated the child while this one waited for the lock.
          child_charge.reload

          Charges::UpdateService.call!(
            charge: child_charge,
            params:,
            cascade_options: {
              cascade: true,
              equal_properties: old_parent.equal_properties?(child_charge),
              equal_applied_pricing_unit_rate: old_parent.equal_applied_pricing_unit_rate?(child_charge)
            }
          )
        end
      end
    end
  end
end
