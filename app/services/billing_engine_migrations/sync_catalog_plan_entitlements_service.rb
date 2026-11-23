# frozen_string_literal: true

module BillingEngineMigrations
  class SyncCatalogPlanEntitlementsService < BaseService
    Result = BaseResult[:created_entitlements, :removed_entitlements, :created_values, :updated_values, :removed_values]

    # entitlements: {feature_code => {privilege_code => value}}, the state the catalog plan ends in.
    # current_entitlements: the live entitlements of the catalog plan with their values loaded, read under a
    # FOR NO KEY UPDATE lock on it, as Entitlement::Concerns::OwnerLockConcern locks a plan for its entitlement writes.
    # features: every live feature of the shadow organization by code, with its privileges loaded.
    def initialize(catalog_plan:, entitlements:, current_entitlements:, features:)
      @catalog_plan = catalog_plan
      @entitlements = entitlements
      @current_entitlements = current_entitlements
      @features = features
      super
    end

    def call
      ActiveRecord::Base.transaction do
        remove_entitlements
        entitlement_ids = kept_entitlement_ids.merge(create_entitlements)
        sync_values(entitlement_ids)
      end

      result
    end

    private

    attr_reader :catalog_plan, :entitlements, :current_entitlements, :features

    def features_by_id
      @features_by_id ||= features.values.index_by(&:id)
    end

    def privileges_by_id
      @privileges_by_id ||= features.values.flat_map(&:privileges).index_by(&:id)
    end

    def existing_entitlements
      @existing_entitlements ||= current_entitlements.filter_map do |entitlement|
        feature = features_by_id[entitlement.entitlement_feature_id]
        [feature.code, entitlement] if feature
      end.to_h
    end

    def kept_entitlement_ids
      existing_entitlements.slice(*entitlements.keys).transform_values(&:id)
    end

    def remove_entitlements
      removed = existing_entitlements.except(*entitlements.keys)
      result.removed_entitlements = removed.keys.sort
      return if removed.empty?

      entitlement_ids = removed.values.map(&:id)
      discard(::Entitlement::EntitlementValue.where(entitlement_entitlement_id: entitlement_ids))
      discard(::Entitlement::Entitlement.where(id: entitlement_ids))
    end

    def create_entitlements
      missing_codes = entitlements.keys.sort - existing_entitlements.keys
      result.created_entitlements = missing_codes
      return {} if missing_codes.empty?

      rows = missing_codes.map do |code|
        {organization_id: catalog_plan.organization_id, catalog_plan_id: catalog_plan.id, entitlement_feature_id: features.fetch(code).id}
      end
      inserted = ::Entitlement::Entitlement.insert_all!(rows, returning: %i[id entitlement_feature_id]) # rubocop:disable Rails/SkipsModelValidations

      inserted.to_h { [features_by_id.fetch(it["entitlement_feature_id"]).code, it["id"]] }
    end

    def sync_values(entitlement_ids)
      result.created_values = []
      result.updated_values = []
      result.removed_values = []
      upserts = []
      removed = []

      entitlements.sort.each do |feature_code, values|
        current = current_values(feature_code)

        values.sort.each do |privilege_code, value|
          existing = current.delete(privilege_code)
          next if existing&.value == value

          (existing ? result.updated_values : result.created_values) << "#{feature_code}.#{privilege_code}"
          upserts << value_row(entitlement_ids.fetch(feature_code), feature_code, privilege_code, value)
        end

        result.removed_values.concat(current.keys.sort.map { "#{feature_code}.#{it}" })
        removed.concat(current.values)
      end

      discard(::Entitlement::EntitlementValue.where(id: removed.map(&:id))) if removed.any?
      upsert_values(upserts) if upserts.any?
    end

    def current_values(feature_code)
      values = existing_entitlements[feature_code]&.values || []
      values.filter_map do |value|
        privilege = privileges_by_id[value.entitlement_privilege_id]
        [privilege.code, value] if privilege
      end.to_h
    end

    def value_row(entitlement_id, feature_code, privilege_code, value)
      {
        organization_id: catalog_plan.organization_id,
        entitlement_entitlement_id: entitlement_id,
        entitlement_privilege_id: features.fetch(feature_code).privileges.find { it.code == privilege_code }.id,
        value:
      }
    end

    def upsert_values(rows)
      ::Entitlement::EntitlementValue.upsert_all( # rubocop:disable Rails/SkipsModelValidations
        rows,
        unique_by: :idx_on_entitlement_privilege_id_entitlement_entitle_9d0542eb1a,
        update_only: %i[value]
      )
    end

    def discard(scope)
      now = Time.current
      scope.update_all(deleted_at: now, updated_at: now) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
