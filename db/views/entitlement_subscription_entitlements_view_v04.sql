WITH
  subscription_entitlements AS (
    SELECT
      fe.entitlement_feature_id,
      fe.plan_id,
      fe.subscription_id,
      fe.created_at,
      fev.deleted_at AS deleted_at,
      fev.id,
      fev.entitlement_privilege_id,
      fev.entitlement_entitlement_id,
      fev.value,
      fev.created_at AS value_created_at
    FROM
      entitlement_entitlement_values fev
        JOIN entitlement_entitlements fe ON fe.id = fev.entitlement_entitlement_id
    WHERE
      fev.deleted_at IS NULL
      AND fe.deleted_at IS NULL
  ),
  all_values AS (
    SELECT
      ep.entitlement_feature_id,
      COALESCE(ep.entitlement_privilege_id, es.entitlement_privilege_id) AS entitlement_privilege_id,
      ep.entitlement_entitlement_id AS plan_entitlement_id,
      es.entitlement_entitlement_id AS override_entitlement_id,
      ep.id AS plan_entitlement_values_id,
      es.id AS override_entitlement_values_id,
      ep.value AS plan_value,
      es.value AS override_value,
      COALESCE(ep.created_at, es.created_at) AS entitlement_created_at,
      COALESCE(ep.value_created_at, es.value_created_at) AS value_created_at
    FROM
      subscription_entitlements ep
        FULL OUTER JOIN subscription_entitlements es ON ep.entitlement_privilege_id = es.entitlement_privilege_id
        AND ep.plan_id IS NOT NULL
        AND es.subscription_id IS NOT NULL
    WHERE
      (
        ep.plan_id IS NOT NULL
          OR es.subscription_id IS NOT NULL
        )
      AND ep.deleted_at IS NULL
      AND es.deleted_at IS NULL
  )
SELECT
  f.id AS entitlement_feature_id,
  f.organization_id AS organization_id,
  fe.plan_id AS plan_id,
  fe.subscription_id AS subscription_id,
  COALESCE(avp.entitlement_created_at, avs.entitlement_created_at, fe.created_at) AS entitlement_created_at,
  f.code AS feature_code,
  f.name AS feature_name,
  f.description AS feature_description,
  f.created_at AS feature_created_at,
  f.deleted_at AS feature_deleted_at,
  pri.id AS entitlement_privilege_id,
  pri.code AS privilege_code,
  pri.name AS privilege_name,
  pri.value_type AS privilege_value_type,
  pri.config AS privilege_config,
  pri.created_at AS privilege_created_at,
  pri.deleted_at AS privilege_deleted_at,
  CASE
    WHEN avs.override_entitlement_id IS NOT NULL THEN COALESCE(avs.plan_entitlement_id, avp.plan_entitlement_id)
    ELSE fe.id
    END AS plan_entitlement_id,
  avs.override_entitlement_id,
  COALESCE(avs.plan_entitlement_values_id, avp.plan_entitlement_values_id) AS plan_entitlement_values_id,
  avs.override_entitlement_values_id,
  COALESCE(avs.plan_value, avp.plan_value) AS privilege_plan_value,
  avs.override_value AS privilege_override_value,
  COALESCE(avp.value_created_at, avs.value_created_at) AS privilege_value_created_at
FROM
  entitlement_entitlements fe
    LEFT JOIN all_values avp ON avp.plan_entitlement_id = fe.id
    LEFT JOIN all_values avs ON avs.override_entitlement_id = fe.id
    LEFT JOIN entitlement_features f ON f.id = fe.entitlement_feature_id
    LEFT JOIN entitlement_privileges pri ON pri.id = COALESCE(avs.entitlement_privilege_id, avp.entitlement_privilege_id)
WHERE
  fe.deleted_at IS NULL;
