# frozen_string_literal: true

class CreateEntitlementView < ActiveRecord::Migration[8.0]
  def up
    safety_assured do
      execute <<~SQL
        CREATE OR REPLACE VIEW subscription_entitlements_view AS
        WITH
        	subscription_entitlements AS (
        		SELECT
        			fe.feature_id,
        			fe.plan_id,
        			fe.subscription_external_id,
        			fev.deleted_at as deleted_at,
        			fev.id,
        			fev.privilege_id,
        			fev.feature_entitlement_id,
        			fev.value
        		FROM
        			feature_entitlement_values fev
        			JOIN feature_entitlements fe ON fe.id = fev.feature_entitlement_id
        			WHERE fev.deleted_at IS NULL
        	),
        	all_values AS (
        		SELECT
        			ep.feature_id,
        			COALESCE(ep.privilege_id, es.privilege_id) AS privilege_id,
        			ep.feature_entitlement_id AS plan_feature_entitlement_id,
        			es.feature_entitlement_id as override_feature_entitlement_id,
        			ep.id AS plan_feature_entitlement_values_id,
        			es.id AS override_feature_entitlement_values_id,
        			ep.value AS plan_value,
        			es.value AS override_value
        		FROM
        			subscription_entitlements ep
        			FULL OUTER JOIN subscription_entitlements es ON ep.privilege_id = es.privilege_id
        			AND ep.plan_id IS NOT NULL
        			AND es.subscription_external_id IS NOT NULL
        		WHERE
        			(
        				ep.plan_id IS NOT NULL
        				OR es.subscription_external_id IS NOT NULL
        			)
        -- 			AND ep.deleted_at IS NULL AND es.deleted_at IS NULL
        	)
        SELECT
        	f.id as feature_id,
        	f.organization_id as organization_id,
        	f.code as feature_code,
        	f.name as feature_name,
        	f.description as feature_description,
        	f.deleted_at as feature_deleted_at,
        	pri.id as privilege_id,
        	pri.code as privilege_code,
        	pri.name as privilege_name,
        	pri.value_type as privilege_value_type,
        	pri.config as privilege_config,
        	pri.deleted_at as privilege_deleted_at,
        	fe.plan_id AS plan_id,
        	fe.subscription_external_id AS subscription_external_id,
        	(sfr.id IS NOT NULL) AS removed,
        	av.plan_feature_entitlement_id,
        	av.override_feature_entitlement_id,
        	av.plan_feature_entitlement_values_id,
        	av.override_feature_entitlement_values_id,
        	av.plan_value AS privilege_plan_value,
        	av.override_value AS privilege_override_value
        FROM
        	feature_entitlements fe
        	LEFT JOIN subscription_feature_entitlement_removals sfr ON fe.feature_id = sfr.feature_id
        	LEFT JOIN all_values av ON COALESCE(av.override_feature_entitlement_id, av.plan_feature_entitlement_id) = fe.id
        	LEFT JOIN features f ON f.id = fe.feature_id
        	LEFT JOIN privileges pri ON pri.id = av.privilege_id
      SQL
    end
  end

  def down
    safety_assured do
      execute "DROP VIEW subscription_entitlements_view"
    end
  end
end
