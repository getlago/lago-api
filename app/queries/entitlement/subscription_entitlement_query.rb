# frozen_string_literal: true

module Entitlement
  class SubscriptionEntitlementQuery < BaseQuery
    Result = BaseResult[:entitlements]
    Filters = BaseFilters[:subscription_id, :plan_id]

    def call
      features_by_id = {}

      ActiveRecord::Base.connection.exec_query(
        sql,
        "subscription_entitlements",
        [filters.plan_id, filters.subscription_id]
      ).each do |row|
        feature_id = row["entitlement_feature_id"]

        features_by_id[feature_id] ||= SubscriptionEntitlement.new(
          "organization_id" => row["organization_id"],
          "entitlement_feature_id" => feature_id,
          "code" => row["feature_code"],
          "name" => row["feature_name"],
          "description" => row["feature_description"],
          "plan_entitlement_id" => row["plan_entitlement_id"],
          "sub_entitlement_id" => row["sub_entitlement_id"],
          "plan_id" => row["plan_id"],
          "subscription_id" => row["subscription_id"],
          "ordering_date" => row["feature_ordering_date"],
          "privileges" => []
        )

        next unless row["privilege_code"] && (row["plan_entitlement_value_id"] || row["sub_entitlement_value_id"])

        features_by_id[feature_id].privileges << SubscriptionEntitlementPrivilege.new(
          "organization_id" => row["organization_id"],
          "entitlement_feature_id" => feature_id,
          "code" => row["privilege_code"],
          "value" => row["value"],
          "plan_value" => row["plan_value"],
          "subscription_value" => row["subscription_value"],
          "name" => row["privilege_name"],
          "value_type" => row["value_type"],
          "config" => row["config"],
          "ordering_date" => row["privilege_ordering_date"],
          "plan_entitlement_id" => row["priv_plan_entitlement_id"],
          "sub_entitlement_id" => row["priv_sub_entitlement_id"],
          "plan_entitlement_value_id" => row["plan_entitlement_value_id"],
          "sub_entitlement_value_id" => row["sub_entitlement_value_id"]
        )
      end

      features_by_id.values
    end

    private

    def sql
      <<~SQL
        -- Narrow down to only the feature IDs relevant to this plan/subscription
        WITH relevant_features AS (
            SELECT DISTINCT entitlement_feature_id
            FROM entitlement_entitlements
            WHERE (plan_id = $1 OR subscription_id = $2)
                AND deleted_at IS NULL
        )
        SELECT
            COALESCE(plan_ent.organization_id, sub_ent.organization_id) AS organization_id,
            f.id AS entitlement_feature_id,
            f.code AS feature_code,
            f.name AS feature_name,
            f.description AS feature_description,
            plan_ent.id AS plan_entitlement_id,
            sub_ent.id AS sub_entitlement_id,
            plan_ent.plan_id,
            sub_ent.subscription_id,
            COALESCE(plan_ent.created_at, sub_ent.created_at) AS feature_ordering_date,
            p.code AS privilege_code,
            p.name AS privilege_name,
            p.value_type,
            p.config,
            COALESCE(sub_val.value, plan_val.value) AS value,
            plan_val.value AS plan_value,
            sub_val.value AS subscription_value,
            COALESCE(plan_val.created_at, sub_val.created_at) AS privilege_ordering_date,
            plan_val.entitlement_entitlement_id AS priv_plan_entitlement_id,
            sub_val.entitlement_entitlement_id AS priv_sub_entitlement_id,
            plan_val.id AS plan_entitlement_value_id,
            sub_val.id AS sub_entitlement_value_id
        FROM
            -- Start from only the features that belong to this plan or subscription
            relevant_features rf
            JOIN entitlement_features f
                ON f.id = rf.entitlement_feature_id
                AND f.deleted_at IS NULL
            -- Find the plan's entitlement for this feature
            LEFT JOIN entitlement_entitlements plan_ent
                ON plan_ent.entitlement_feature_id = f.id
                AND plan_ent.plan_id = $1
                AND plan_ent.deleted_at IS NULL
            -- Find the subscription's entitlement for this feature
            LEFT JOIN entitlement_entitlements sub_ent
                ON sub_ent.entitlement_feature_id = f.id
                AND sub_ent.subscription_id = $2
                AND sub_ent.deleted_at IS NULL
            -- Find privileges defined for this feature
            LEFT JOIN entitlement_privileges p
                ON p.entitlement_feature_id = f.id
                AND p.deleted_at IS NULL
            -- Find the plan's value for this privilege
            LEFT JOIN entitlement_entitlement_values plan_val
                ON plan_val.entitlement_entitlement_id = plan_ent.id
                AND plan_val.entitlement_privilege_id = p.id
                AND plan_val.deleted_at IS NULL
            -- Find the subscription's value for this privilege
            LEFT JOIN entitlement_entitlement_values sub_val
                ON sub_val.entitlement_entitlement_id = sub_ent.id
                AND sub_val.entitlement_privilege_id = p.id
                AND sub_val.deleted_at IS NULL
        WHERE
            -- Feature not removed from subscription
            NOT EXISTS (
                SELECT 1 FROM entitlement_subscription_feature_removals
                WHERE subscription_id = $2
                    AND entitlement_feature_id = f.id
                    AND deleted_at IS NULL
            )
            -- Privilege not removed from subscription
            AND (
                p.id IS NULL
                OR NOT EXISTS (
                    SELECT 1 FROM entitlement_subscription_feature_removals
                    WHERE subscription_id = $2
                        AND entitlement_privilege_id = p.id
                        AND deleted_at IS NULL
                )
            )
        ORDER BY
            feature_ordering_date, privilege_ordering_date
      SQL
    end
  end
end
