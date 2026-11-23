# frozen_string_literal: true

module BillingEngineMigrations
  class CopyFeaturesService < BaseService
    Result = BaseResult[:features, :created_features, :created_privileges, :updated_privileges]

    def initialize(migration:)
      @migration = migration
      super
    end

    def call
      return result.validation_failure!(errors: mismatched_privileges) if mismatched_privileges.any?

      ActiveRecord::Base.transaction do
        create_missing_features
        create_missing_privileges
        update_select_options
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
      migration.shadow_organization.features.includes(:privileges).index_by(&:code)
    end

    def source_and_shadow_privileges
      source_features.flat_map do |feature|
        feature.privileges.sort_by(&:code).filter_map do |privilege|
          shadow_privilege = shadow_features[feature.code]&.privileges&.find { it.code == privilege.code }
          [feature.code, privilege, shadow_privilege] if shadow_privilege
        end
      end
    end

    def mismatched_privileges
      @mismatched_privileges ||= source_and_shadow_privileges.each_with_object({}) do |(feature_code, privilege, shadow), errors|
        error = mismatch_error(privilege, shadow)
        errors[:"#{feature_code}.#{privilege.code}"] = [error] if error
      end
    end

    # An organization can add select options to a privilege but never remove one, so a shadow
    # privilege whose options are all still in the organization only lags behind it.
    def mismatch_error(privilege, shadow_privilege)
      if privilege.value_type != shadow_privilege.value_type
        "value_type_mismatch"
      elsif (select_options(shadow_privilege) - select_options(privilege)).any?
        "select_options_mismatch"
      end
    end

    def select_options(privilege)
      privilege.config.fetch("select_options", [])
    end

    def create_missing_features
      missing = source_features.reject { shadow_features.key?(it.code) }
      result.created_features = []
      return if missing.empty?

      rows = missing.map do |feature|
        {organization_id: migration.shadow_organization_id, code: feature.code, name: feature.name, description: feature.description}
      end
      inserted = ::Entitlement::Feature.insert_all(rows, unique_by: :idx_features_code_unique_per_organization, returning: %i[code]) # rubocop:disable Rails/SkipsModelValidations
      result.created_features = inserted.pluck("code").sort
      @shadow_features = load_shadow_features
    end

    def create_missing_privileges
      missing = source_features.flat_map { |feature| missing_privileges(feature).map { [feature.code, it] } }
      result.created_privileges = []
      return if missing.empty?

      rows = missing.map { |feature_code, privilege| privilege_row(shadow_features.fetch(feature_code), privilege) }
      inserted = ::Entitlement::Privilege.insert_all( # rubocop:disable Rails/SkipsModelValidations
        rows,
        unique_by: :idx_privileges_code_unique_per_feature,
        returning: %i[entitlement_feature_id code]
      )

      feature_codes = shadow_features.values.to_h { [it.id, it.code] }
      result.created_privileges = inserted.map { "#{feature_codes.fetch(it["entitlement_feature_id"])}.#{it["code"]}" }.sort
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

    def update_select_options
      outdated = source_and_shadow_privileges.select { |_, privilege, shadow| privilege.config != shadow.config }
      result.updated_privileges = outdated.map { |feature_code, privilege, _| "#{feature_code}.#{privilege.code}" }

      outdated.each do |_, privilege, shadow|
        ::Entitlement::Privilege.where(id: shadow.id).update_all(config: privilege.config, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      end
    end
  end
end
