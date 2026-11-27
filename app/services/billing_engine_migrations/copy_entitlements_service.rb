# frozen_string_literal: true

module BillingEngineMigrations
  class CopyEntitlementsService < BaseService
    Result = BaseResult[
      :created_features,
      :created_privileges,
      :updated_privileges,
      :removed_privileges,
      :catalog_plans,
      :missing_plan_codes,
      :missing_catalog_plan_codes,
      :conflicting_catalog_plan_codes
    ]

    def initialize(migration:)
      @migration = migration
      super
    end

    def call
      return result.forbidden_failure!(code: "migration_not_shadowing") unless migration.shadowing?

      ActiveRecord::Base.transaction do
        features_result = CopyFeaturesService.call!(migration:)
        result.created_features = features_result.created_features
        result.created_privileges = features_result.created_privileges
        result.updated_privileges = features_result.updated_privileges
        result.removed_privileges = features_result.removed_privileges

        sync_catalog_plans(features_result.features)
      end

      result.missing_plan_codes = (plan_mapping.keys - plans.map(&:code)).sort
      result.missing_catalog_plan_codes = (plan_mapping.values - catalog_plans.keys).uniq.sort
      result
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e)
    end

    private

    attr_reader :migration

    delegate :plan_mapping, to: :migration

    def sync_catalog_plans(features)
      result.catalog_plans = {}
      result.conflicting_catalog_plan_codes = []

      entitlements_by_catalog_plan_code.slice(*catalog_plans.keys).sort.each do |catalog_plan_code, entitlement_sets|
        catalog_plan = catalog_plans.fetch(catalog_plan_code)

        if entitlement_sets.uniq.many?
          result.conflicting_catalog_plan_codes << catalog_plan_code
        else
          result.catalog_plans[catalog_plan_code] = SyncCatalogPlanEntitlementsService.call!(
            catalog_plan:,
            entitlements: entitlement_sets.first,
            current_entitlements: current_entitlements.fetch(catalog_plan.id, []),
            features:
          )
        end
      end
    end

    def entitlements_by_catalog_plan_code
      plans.group_by { plan_mapping.fetch(it.code) }.transform_values { |grouped| grouped.map { entitlements_of(it) } }
    end

    def entitlements_of(plan)
      plan.entitlements.select(&:feature).to_h do |entitlement|
        values = entitlement.values.select(&:privilege).to_h { [it.privilege.code, it.value] }
        [entitlement.feature.code, values]
      end
    end

    def plans
      @plans ||= migration.organization.plans
        .where(parent_id: nil, code: plan_mapping.keys)
        .includes(entitlements: [:feature, {values: :privilege}])
        .to_a
    end

    # Locked in one query and in code order, so two runs cannot deadlock. Under FOR NO KEY UPDATE, PostgreSQL
    # rechecks deleted_at on a row discarded meanwhile and leaves it out, so it is reported as missing.
    def catalog_plans
      @catalog_plans ||= migration.shadow_organization.catalog_plans
        .where(code: plan_mapping.values)
        .order(:code)
        .lock("FOR NO KEY UPDATE")
        .index_by(&:code)
    end

    def current_entitlements
      @current_entitlements ||= ::Entitlement::Entitlement
        .where(catalog_plan_id: catalog_plans.values.map(&:id))
        .includes(:values)
        .group_by(&:catalog_plan_id)
    end
  end
end
