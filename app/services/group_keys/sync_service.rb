# frozen_string_literal: true

module GroupKeys
  class SyncService < BaseService
    Result = BaseResult

    def initialize(owner:, properties:)
      @owner = owner
      @properties = properties || {}

      super
    end

    def call
      pricing_keys = Array(properties["pricing_group_keys"])
      presentation_keys = Array(properties["presentation_group_keys"])

      sync_keys(pricing_keys, "pricing")
      sync_keys(presentation_keys, "presentation")

      result
    end

    private

    attr_reader :owner, :properties

    def sync_keys(keys, key_type)
      existing = owner.group_keys.where(key_type:)
      existing_keys = existing.pluck(:key)

      # Create new keys
      keys_to_create = keys - existing_keys
      keys_to_create.each do |key|
        owner.group_keys.create!(
          organization: owner.organization,
          charge: charge_for_owner,
          charge_filter: charge_filter_for_owner,
          key:,
          key_type:
        )
      end

      # Soft-delete removed keys
      keys_to_remove = existing_keys - keys
      existing.where(key: keys_to_remove).find_each(&:discard!)
    end

    def charge_for_owner
      if owner.is_a?(Charge)
        owner
      else
        owner.charge
      end
    end

    def charge_filter_for_owner
      if owner.is_a?(ChargeFilter)
        owner
      end
    end
  end
end
