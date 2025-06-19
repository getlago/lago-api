# frozen_string_literal: true

class CreateEntitlementView < ActiveRecord::Migration[8.0]
  def up
    safety_assured do
      execute <<~SQL
        CREATE OR REPLACE VIEW entitlements_view AS
        WITH
        	subscription_entitlements AS (
        		SELECT
        			fev.*,
        			fe.plan_id,
        			fe.subscription_external_id,
        			fe.feature_id
        		FROM
        			feature_entitlement_values fev
        			JOIN feature_entitlements fe ON fe.id = fev.feature_entitlement_id
        	),
        	all_values AS (
        		SELECT
        			p.feature_id,
        			COALESCE(es.feature_entitlement_id, ep.feature_entitlement_id) AS feature_entitlement_id,
        			ep.privilege_id AS privilege_id,
        			ep.value AS plan_value,
        			es.value AS override_value,
        			p.*
        		FROM
        			subscription_entitlements ep
        			FULL OUTER JOIN subscription_entitlements es ON ep.privilege_id = es.privilege_id
        			AND ep.plan_id IS NOT NULL
        			AND es.subscription_external_id IS NOT NULL
        			JOIN privileges p ON p.id = COALESCE(ep.privilege_id, es.privilege_id)
        		WHERE
        			(
        				ep.plan_id IS NOT NULL
        				OR es.subscription_external_id IS NOT NULL
        			)
        	)
        SELECT
          fe.feature_id,
        	fe.id AS feature_entitlement_id,
        	fe.plan_id AS plan_id,
        	fe.subscription_external_id AS subscription_external_id,
	        (sfr.id IS NOT NULL) AS removed,
        	av.privilege_id AS privilege_id,
        	av.code AS privilege_code,
        	av.name AS privilege_name,
        	av.value_type as privilege_value_type,
        	av.plan_value as privilege_plan_value,
        	av.override_value as privilege_override_value
        FROM
        	feature_entitlements fe
        	LEFT JOIN subscription_feature_removals sfr ON fe.feature_id = sfr.feature_id
        	LEFT JOIN all_values av ON av.feature_entitlement_id = fe.id
      SQL
    end
  end

  def down
    safety_assured do
      execute "DROP VIEW entitlements_view"
    end
  end
end
