# frozen_string_literal: true

module Entitlement
  class SubscriptionEntitlementQuery < BaseQuery
    Result = BaseResult[:entitlements]
    Filters = BaseFilters[:subscription_id, :plan_id]

    def call
      rows = ActiveRecord::Base.connection.exec_query(
        combined_sql,
        "subscription_entitlements",
        [filters.plan_id, filters.subscription_id]
      )

      features_by_id = {}

      rows.each do |row|
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

        next unless row["privilege_code"]

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

    def combined_sql
      <<~SQL
        WITH
            plan_entitlements AS (
                SELECT
                    id, organization_id, entitlement_feature_id, plan_id, created_at
                FROM
                    entitlement_entitlements
                WHERE
                    plan_id = $1
                    AND deleted_at IS NULL
            ),
            sub_entitlements AS (
                SELECT
                    id, organization_id, entitlement_feature_id, subscription_id, created_at
                FROM
                    entitlement_entitlements
                WHERE
                    subscription_id = $2
                    AND deleted_at IS NULL
            ),
            features AS (
                SELECT
                    COALESCE(pe.organization_id, se.organization_id) AS organization_id,
                    COALESCE(pe.entitlement_feature_id, se.entitlement_feature_id) AS entitlement_feature_id,
                    f.code AS feature_code,
                    f.name AS feature_name,
                    f.description AS feature_description,
                    pe.id AS plan_entitlement_id,
                    se.id AS sub_entitlement_id,
                    pe.plan_id,
                    se.subscription_id,
                    COALESCE(pe.created_at, se.created_at) AS feature_ordering_date
                FROM
                    plan_entitlements pe
                    FULL OUTER JOIN sub_entitlements se ON pe.entitlement_feature_id = se.entitlement_feature_id
                    JOIN entitlement_features f ON f.id = COALESCE(pe.entitlement_feature_id, se.entitlement_feature_id)
                WHERE
                    f.deleted_at IS NULL
                    AND (
                        pe.entitlement_feature_id IS NULL
                        OR NOT EXISTS (
                            SELECT 1
                            FROM entitlement_subscription_feature_removals
                            WHERE
                                subscription_id = $2
                                AND entitlement_feature_id = pe.entitlement_feature_id
                                AND deleted_at IS NULL
                        )
                    )
            ),
            plan_values AS (
                SELECT
                    id, entitlement_entitlement_id, entitlement_privilege_id, value, created_at
                FROM
                    entitlement_entitlement_values
                WHERE
                    deleted_at IS NULL
                    AND entitlement_entitlement_id IN (
                        SELECT plan_entitlement_id FROM features WHERE plan_entitlement_id IS NOT NULL
                    )
            ),
            sub_values AS (
                SELECT
                    id, entitlement_entitlement_id, entitlement_privilege_id, value, created_at
                FROM
                    entitlement_entitlement_values
                WHERE
                    deleted_at IS NULL
                    AND entitlement_entitlement_id IN (
                        SELECT sub_entitlement_id FROM features WHERE sub_entitlement_id IS NOT NULL
                    )
            ),
            privileges AS (
                SELECT
                    p.entitlement_feature_id,
                    p.code AS privilege_code,
                    p.name AS privilege_name,
                    p.value_type,
                    p.config,
                    COALESCE(sv.value, pv.value) AS value,
                    pv.value AS plan_value,
                    sv.value AS subscription_value,
                    COALESCE(pv.created_at, sv.created_at) AS privilege_ordering_date,
                    pv.entitlement_entitlement_id AS priv_plan_entitlement_id,
                    sv.entitlement_entitlement_id AS priv_sub_entitlement_id,
                    pv.id AS plan_entitlement_value_id,
                    sv.id AS sub_entitlement_value_id
                FROM
                    plan_values pv
                    FULL OUTER JOIN sub_values sv ON pv.entitlement_privilege_id = sv.entitlement_privilege_id
                    JOIN entitlement_privileges p ON p.id = COALESCE(pv.entitlement_privilege_id, sv.entitlement_privilege_id)
                WHERE
                    p.deleted_at IS NULL
                    AND (
                        pv.entitlement_privilege_id IS NULL
                        OR NOT EXISTS (
                            SELECT 1
                            FROM entitlement_subscription_feature_removals
                            WHERE
                                subscription_id = $2
                                AND entitlement_privilege_id = pv.entitlement_privilege_id
                                AND deleted_at IS NULL
                        )
                    )
            )
        SELECT
            feat.organization_id,
            feat.entitlement_feature_id,
            feat.feature_code,
            feat.feature_name,
            feat.feature_description,
            feat.plan_entitlement_id,
            feat.sub_entitlement_id,
            feat.plan_id,
            feat.subscription_id,
            feat.feature_ordering_date,
            priv.privilege_code,
            priv.privilege_name,
            priv.value_type,
            priv.config,
            priv.value,
            priv.plan_value,
            priv.subscription_value,
            priv.privilege_ordering_date,
            priv.priv_plan_entitlement_id,
            priv.priv_sub_entitlement_id,
            priv.plan_entitlement_value_id,
            priv.sub_entitlement_value_id
        FROM
            features feat
            LEFT JOIN privileges priv ON priv.entitlement_feature_id = feat.entitlement_feature_id
        ORDER BY
            feat.feature_ordering_date, priv.privilege_ordering_date
      SQL
    end
  end
end
