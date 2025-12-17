# frozen_string_literal: true

class MigrateDisableProgressiveBillingFlagOnSubscription < ActiveRecord::Migration[8.0]
  def up
    update_query = <<~SQL
      WITH
          -- Step 1: Get all child plans (plans that have a parent and are not deleted)
          child_plans AS (
              SELECT
                  id,
                  parent_id
              FROM
                  plans
              WHERE
                  parent_id IS NOT NULL
                  AND deleted_at IS NULL
          ),
          -- Step 2: Get all plan IDs that have at least one active usage threshold
          plans_with_thresholds AS (
              SELECT DISTINCT
                  plan_id
              FROM
                  usage_thresholds
              WHERE
                  deleted_at IS NULL
                  AND plan_id IS NOT NULL
          ),
          -- Step 3: Find child plans where parent HAS thresholds but child does NOT
          child_plans_missing_thresholds AS (
              SELECT
                  cp.id AS child_plan_id,
                  cp.parent_id
              FROM
                  child_plans cp
                  -- Parent has thresholds
                  INNER JOIN plans_with_thresholds pwt ON pwt.plan_id = cp.parent_id
                  -- Child does NOT have thresholds
              WHERE
                  cp.id NOT IN (
                      SELECT
                          plan_id
                      FROM
                          plans_with_thresholds
                  )
          )

      -- Step 4: Update the matching subscriptions
      UPDATE subscriptions
      SET
          disable_progressive_billing = TRUE
      WHERE
          plan_id IN (
              SELECT
                  child_plan_id
              FROM
                  child_plans_missing_thresholds
         );
    SQL

    safety_assured { execute(update_query) }
  end

  def down
    # No action needed
  end
end
