# frozen_string_literal: true

module BillingEngineMigrations
  class CopyFeaturesService < BaseService
    Result = BaseResult[:features, :created_features, :created_privileges, :updated_privileges, :removed_privileges]

    def initialize(migration:)
      @migration = migration
      super
    end

    def call
      ActiveRecord::Base.transaction do
        remove_outdated_privileges
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

    def remove_outdated_privileges
      outdated = outdated_shadow_privileges
      result.removed_privileges = outdated.map { |feature_code, privilege| "#{feature_code}.#{privilege.code}" }.sort
      return if outdated.empty?

      privilege_ids = outdated.map { |_, privilege| privilege.id }
      discard(::Entitlement::EntitlementValue.where(entitlement_privilege_id: privilege_ids))
      discard(::Entitlement::Privilege.where(id: privilege_ids))
      @shadow_features = load_shadow_features
    end

    def outdated_shadow_privileges
      source_features.flat_map do |feature|
        shadow_feature = shadow_features[feature.code]
        next [] unless shadow_feature

        shadow_feature.privileges.filter_map do |shadow_privilege|
          privilege = feature.privileges.find { it.code == shadow_privilege.code }
          [feature.code, shadow_privilege] if privilege.nil? || recreated?(privilege, shadow_privilege)
        end
      end
    end

    # An organization can add select options to a privilege but never change its value type or
    # remove an option in place, so a shadow privilege that differs that way was discarded and
    # recreated in the organization.
    def recreated?(privilege, shadow_privilege)
      privilege.value_type != shadow_privilege.value_type ||
        (select_options(shadow_privilege) - select_options(privilege)).any?
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

      return if outdated.empty?

      rows = outdated.map do |_, privilege, shadow|
        shadow.attributes.slice("id", "organization_id", "entitlement_feature_id", "code", "name", "value_type")
          .merge("config" => privilege.config)
      end
      ::Entitlement::Privilege.upsert_all(rows, update_only: %i[config]) # rubocop:disable Rails/SkipsModelValidations
    end

    def discard(scope)
      now = Time.current
      scope.update_all(deleted_at: now, updated_at: now) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
