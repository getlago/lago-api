# frozen_string_literal: true

module BillingEngineMigrations
  class CopyFeaturesService < BaseService
    Result = BaseResult[:features, :created_features, :created_privileges]

    def initialize(migration:)
      @migration = migration
      super
    end

    def call
      return result.validation_failure!(errors: mismatched_privileges) if mismatched_privileges.any?

      ActiveRecord::Base.transaction do
        create_missing_features
        create_missing_privileges
      end

      result.features = load_shadow_features
      result
    end

    private

    attr_reader :migration

    def source_features
      @source_features ||= migration.organization.features.includes(:privileges).order(:code).to_a
    end

    def shadow_features
      @shadow_features ||= load_shadow_features
    end

    def load_shadow_features
      ::Entitlement::Feature
        .where(organization_id: migration.shadow_organization_id, code: source_features.map(&:code))
        .includes(:privileges)
        .index_by(&:code)
    end

    def mismatched_privileges
      @mismatched_privileges ||= source_features.each_with_object({}) do |feature, errors|
        feature.privileges.each do |privilege|
          shadow_privilege = shadow_features[feature.code]&.privileges&.find { it.code == privilege.code }
          error = shadow_privilege && mismatch_error(privilege, shadow_privilege)
          errors[:"#{feature.code}.#{privilege.code}"] = [error] if error
        end
      end
    end

    def mismatch_error(privilege, shadow_privilege)
      if privilege.value_type != shadow_privilege.value_type
        "value_type_mismatch"
      elsif privilege.config != shadow_privilege.config
        "select_options_mismatch"
      end
    end

    def create_missing_features
      missing = source_features.reject { shadow_features.key?(it.code) }
      result.created_features = missing.map(&:code)
      return if missing.empty?

      rows = missing.map do |feature|
        {organization_id: migration.shadow_organization_id, code: feature.code, name: feature.name, description: feature.description}
      end
      ::Entitlement::Feature.insert_all(rows, unique_by: :idx_features_code_unique_per_organization) # rubocop:disable Rails/SkipsModelValidations
      @shadow_features = load_shadow_features
    end

    def create_missing_privileges
      missing = source_features.flat_map { |feature| missing_privileges(feature).map { [feature.code, it] } }
      result.created_privileges = missing.map { |feature_code, privilege| "#{feature_code}.#{privilege.code}" }
      return if missing.empty?

      rows = missing.map { |feature_code, privilege| privilege_row(shadow_features.fetch(feature_code), privilege) }
      ::Entitlement::Privilege.insert_all(rows, unique_by: :idx_privileges_code_unique_per_feature) # rubocop:disable Rails/SkipsModelValidations
    end

    def missing_privileges(feature)
      shadow_codes = shadow_features.fetch(feature.code).privileges.map(&:code)
      feature.privileges.reject { shadow_codes.include?(it.code) }.sort_by(&:code)
    end

    def privilege_row(shadow_feature, privilege)
      {
        organization_id: migration.shadow_organization_id,
        entitlement_feature_id: shadow_feature.id,
        code: privilege.code,
        name: privilege.name,
        value_type: privilege.value_type,
        config: privilege.config
      }
    end
  end
end
