# frozen_string_literal: true

module UsageAttributionTypes
  class UpdateService < BaseService
    Result = BaseResult[:usage_attribution_type]

    def initialize(usage_attribution_type:, params:)
      @usage_attribution_type = usage_attribution_type
      @params = params.to_h.with_indifferent_access
      super
    end

    def call
      return result.not_found_failure!(resource: "usage_attribution_type") unless usage_attribution_type

      usage_attribution_type.name = params[:name] if params.key?(:name)
      usage_attribution_type.code = params[:code]&.strip if params.key?(:code)
      usage_attribution_type.attribution_key = params[:attribution_key]&.strip if params.key?(:attribution_key)
      usage_attribution_type.role = params[:role] if params.key?(:role)
      usage_attribution_type.parent_id = params[:parent_id].presence if params.key?(:parent_id)

      frozen_changes = usage_attribution_type.changed.map(&:to_sym) - [:name]
      if attributed? && frozen_changes.any?
        return result.validation_failure!(errors: frozen_changes.index_with { ["usage_already_attributed"] })
      end

      if usage_attribution_type.parent_id_changed? && usage_attribution_type.parent_id.present? &&
          !organization.usage_attribution_types.exists?(id: usage_attribution_type.parent_id)
        return result.not_found_failure!(resource: "parent_usage_attribution_type")
      end

      if usage_attribution_type.flat? && usage_attribution_type.children.exists?
        return result.single_validation_failure!(field: :role, error_code: "cannot_be_flat_with_children")
      end

      usage_attribution_type.save!

      result.usage_attribution_type = usage_attribution_type
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :usage_attribution_type, :params

    delegate :organization, to: :usage_attribution_type

    def attributed?
      usage_attribution_type.usage_attribution_values.exists?
    end
  end
end
