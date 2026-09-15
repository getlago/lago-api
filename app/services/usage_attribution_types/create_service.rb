# frozen_string_literal: true

module UsageAttributionTypes
  class CreateService < BaseService
    Result = BaseResult[:usage_attribution_type]

    def initialize(organization:, params:)
      @organization = organization
      @params = params.to_h.with_indifferent_access
      super
    end

    def call
      return result.not_found_failure!(resource: "organization") unless organization

      parent = nil
      if params[:parent_id].present?
        parent = organization.usage_attribution_types.find_by(id: params[:parent_id])
        return result.not_found_failure!(resource: "parent_usage_attribution_type") unless parent
      end

      usage_attribution_type = organization.usage_attribution_types.create!(
        code: params[:code]&.strip,
        name: params[:name],
        attribution_key: params[:attribution_key]&.strip,
        role: params[:role],
        parent:
      )

      result.usage_attribution_type = usage_attribution_type
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :organization, :params
  end
end
