WITH
  -- Number of subscriptions per plan
	plan_subcriptions AS (
		SELECT
			COALESCE(plans.parent_id, plan_id) AS plan_id,
			COUNT(*)
		FROM
			subscriptions
			INNER JOIN plans ON plans.id = subscriptions.plan_id
		WHERE
			plans.deleted_at IS NULL
			AND subscriptions.status IN (0, 1)
		GROUP BY
			COALESCE(plans.parent_id, plan_id)
	),
  -- Number of subscriptions that have the feature through a plan
	plan_subcriptions_count AS (
		SELECT
			plan_features.entitlement_feature_id,
			SUM(COUNt) AS count
		FROM
			entitlement_entitlements AS plan_features
			INNER JOIN plan_subcriptions ON plan_subcriptions.plan_id = plan_features.plan_id
		WHERE
			plan_features.plan_id IS NOT NULL
			AND plan_features.deleted_at IS NULL
		GROUP BY
			plan_features.entitlement_feature_id
	),
  -- Number of subscriptions that have the feature assigned directly
	direct_subscriptions_count AS (
		SELECT
			subscription_features.entitlement_feature_id,
			COUNT(*) AS count
		FROM
			entitlement_entitlements AS subscription_features
			INNER JOIN subscriptions ON subscriptions.id = subscription_features.subscription_id
			INNER JOIN plans ON plans.id = subscriptions.plan_id
		WHERE
			subscription_features.deleted_at IS NULL
			AND subscription_features.subscription_id IS NOT NULL
			AND subscriptions.status IN (0, 1)
			AND plans.deleted_at IS NULL
      -- Avoid counting the same subscription twice if the feature is assigned both directly and through a plan
			AND NOT EXISTS (
				SELECT
					1
				FROM
					entitlement_entitlements AS plan_features
				WHERE
					plan_features.plan_id = COALESCE(plans.parent_id, plans.id)
					AND plan_features.entitlement_feature_id = subscription_features.entitlement_feature_id
					AND plan_features.plan_id IS NOT NULL
					AND plan_features.deleted_at IS NULL
			)
		GROUP BY
			subscription_features.entitlement_feature_id
	),
  -- Number of subscriptions where the feature has been manually removed
	feature_removals_count AS (
		SELECT
			feature_removals.entitlement_feature_id,
			COUNT(*) AS count
		FROM
			entitlement_subscription_feature_removals AS feature_removals
			INNER JOIN subscriptions ON subscriptions.id = feature_removals.subscription_id
		WHERE
			feature_removals.entitlement_feature_id IS NOT NULL
			AND subscriptions.status IN (0, 1)
			AND feature_removals.deleted_at IS NULL
		GROUP BY
			feature_removals.entitlement_feature_id
	)
SELECT
	COALESCE(plan_subcriptions_count.entitlement_feature_id, direct_subscriptions_count.entitlement_feature_id) AS entitlement_feature_id,
	COALESCE(plan_subcriptions_count.count, 0) + COALESCE(direct_subscriptions_count.count, 0) - COALESCE(feature_removals_count.count, 0) AS count
FROM
	plan_subcriptions_count
	FULL JOIN direct_subscriptions_count ON plan_subcriptions_count.entitlement_feature_id = direct_subscriptions_count.entitlement_feature_id
	LEFT JOIN feature_removals_count ON plan_subcriptions_count.entitlement_feature_id = feature_removals_count.entitlement_feature_id
