# frozen_string_literal: true

module Entitlement
  class FeatureUpdateService < BaseService
    Result = BaseResult[:feature]

    def initialize(feature:, params:)
      @feature = feature
      @params = params
      super
    end

    def call
      return result.not_found_failure!(resource: "feature") unless feature

      ActiveRecord::Base.transaction do
        update_feature_attributes
        update_privileges if params[:privileges].present?

        feature.save!
      end

      result.feature = feature
      result
    rescue ActiveRecord::RecordInvalid => e
      if e.record.is_a?(Privilege)
        errors = e.record.errors.messages.transform_keys { |key| :"privilege.#{key}" }
        result.validation_failure!(errors:)
      else
        result.record_validation_failure!(record: e.record)
      end
    end

    private

    attr_reader :feature, :params

    def update_feature_attributes
      feature.name = params[:name] if params.key?(:name)
      feature.description = params[:description] if params.key?(:description)
    end

    def update_privileges
      params[:privileges].each do |code, privilege_params|
        privilege = feature.privileges.find { it[:code] == code }
        next unless privilege

        privilege.name = privilege_params[:name] if privilege_params.key?(:name)
        privilege.save!
      end
    end
  end
end
