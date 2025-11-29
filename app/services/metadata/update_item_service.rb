# frozen_string_literal: true

module Metadata
  # Updates the metadata of the record with new content
  #
  # It behaves differently based on the `replace` flag and the content of the old and new value:
  # ```
  # ----------+-----------+---------+-------------------------
  # old value | new value | replace | action
  # ----------+-----------+---------+-------------------------
  #   nil     |    nil    |   any   | no-op
  #   nil     |   non-nil |   any   | set new value
  #  non-nil  |    nil    |  false  | no-op
  #  non-nil  |    nil    |  true   | delete metadata item
  #  non-nil  |   non-nil |  false  | merge new value
  #  non-nil  |   non-nil |  true   | replace with new value
  # ----------+-----------+---------+-------------------------
  # ```
  #
  # To keep the service owner-agnostic for future updates,
  # it accepts any ActiveRecord model as owner,
  # but returns an error if the owner does not have metadata.
  #
  # Can either replace the existing content or merge new non-empty value with it.
  #
  # When `preview: true` is passed, the service builds metadata objects in memory
  # without persisting them to the database. The owner's `metadata` and `metadata_id`
  # attributes are modified in memory, but nothing is saved.
  class UpdateItemService < BaseService
    use Middlewares::Yabeda::DurationMiddleware

    Result = BaseResult[:owner, :value, :replace, :preview]

    # @param [ActiveRecord::Base] owner The record whose metadata is to be updated
    # @option [#to_h] :value The new content of the metadata item
    # @option [Boolean] :replace Whether to replace the existing content or merge with it
    # @option [Boolean] :preview When true, builds objects in memory without persisting
    def initialize(owner, value:, replace: false, preview: false)
      super()

      result.value = value
      result.owner = owner
      result.replace = replace
      result.preview = preview
    end

    def call
      unless metadata_supported?
        return result.not_allowed_failure!(code: "metadata_not_supported")
      end

      # TODO: Simplify the logic
      #   The owner refers back to its metadata via the composite FK:
      #   (metadata_id, id, organization_id) -> (id, owner_id, organization_id)
      #   In Postgres 14 and earlier, ON DELETE CASCADE does NOT have a SET NULL option for a particular column
      #   of the composite foreign key, that's why we cannot delete the metadata item before
      #   saving the owner record with a `metadata_id: nil`.
      #   After migration to Postgres 15+, the foreign key could receive the clause
      #   `ON DELETE SET NULL (metadata_id)` for the `metadata_id` column,
      #   in which case `change_metadata!` could delete the metadata item by itself.
      ActiveRecord::Base.transaction do
        change_metadata!
        next result if preview

        owner.save! if owner.changed?
        metadata.destroy! if delete_metadata?
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    delegate :owner, :value, :replace, :preview, to: :result
    delegate :metadata, :metadata_id, :organization_id, to: :owner

    # the `metadata` is a `has_one` association,
    # while the `metadata_id` is the other way fk-protected reference.
    # both must be present to ensure the owner supports metadata.
    def metadata_supported?
      owner.respond_to?(:organization_id) && owner.respond_to?(:metadata) && owner.respond_to?(:metadata_id)
    end

    def create_metadata?
      metadata_id.blank? && !value.nil? && (value.present? || replace)
    end

    def replace_metadata?
      metadata_id.present? && replace && !value.nil?
    end

    def merge_metadata?
      metadata_id.present? && !replace && value.present?
    end

    def delete_metadata?
      return @delete_metadata if defined?(@delete_metadata)
      @delete_metadata = metadata_id.present? && replace && value.nil?
    end

    def change_metadata!
      if delete_metadata?
        owner.metadata_id = nil
      elsif create_metadata?
        owner.id ||= SecureRandom.uuid
        new_metadata = owner.build_metadata(id: SecureRandom.uuid, organization_id:, value:)
        new_metadata.save! unless preview
        owner.metadata_id = new_metadata.id
      elsif replace_metadata?
        metadata.value = value
        metadata.save! unless preview
      elsif merge_metadata?
        metadata.value = metadata.value.merge(value)
        metadata.save! unless preview
      end
    end
  end
end
