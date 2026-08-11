# frozen_string_literal: true

class SoftDeleteDuplicateChildCharges < ActiveRecord::Migration[8.0]
  # NOTE: Child charges (parent_id set) are materialized on overridden plans by cascade
  #       jobs; overlapping cascades could materialize the same parent charge several
  #       times on a child plan. Each copy is billed, multiplying usage and invoices.
  #
  #       Only exact copies are safe to remove automatically: charges sharing
  #       (plan_id, parent_id) AND identical in every billing attribute (scalar columns,
  #       taxes, pricing unit, filters). For those, any copy is interchangeable — keep the
  #       oldest, soft-delete the rest with their filters.
  #
  #       Copies that diverged (e.g. one was later customized for the subscription) are
  #       left untouched: no rule can tell which one carries the intended pricing. They
  #       must be resolved by a human; the next migration (unique index) fails with
  #       instructions while any remain.
  def up
    safety_assured do
      execute <<~SQL
        WITH duplicate_groups AS (
          SELECT plan_id, parent_id
          FROM charges
          WHERE parent_id IS NOT NULL AND deleted_at IS NULL
          GROUP BY plan_id, parent_id
          HAVING count(*) > 1
        ),
        signatures AS (
          SELECT
            c.id, c.plan_id, c.parent_id, c.created_at,
            jsonb_build_object(
              'billable_metric_id',    c.billable_metric_id,
              'amount_currency',       c.amount_currency,
              'charge_model',          c.charge_model,
              'properties',            c.properties,
              'pay_in_advance',        c.pay_in_advance,
              'min_amount_cents',      c.min_amount_cents,
              'invoiceable',           c.invoiceable,
              'prorated',              c.prorated,
              'invoice_display_name',  c.invoice_display_name,
              'regroup_paid_fees',     c.regroup_paid_fees,
              'accepts_target_wallet', c.accepts_target_wallet,
              'tax_ids', (
                SELECT coalesce(jsonb_agg(ct.tax_id ORDER BY ct.tax_id), '[]'::jsonb)
                FROM charges_taxes ct
                WHERE ct.charge_id = c.id
              ),
              'pricing_unit', (
                SELECT jsonb_build_array(apu.pricing_unit_id, apu.conversion_rate)
                FROM applied_pricing_units apu
                WHERE apu.pricing_unitable_type = 'Charge'
                  AND apu.pricing_unitable_id = c.id
              ),
              'filters', (
                SELECT coalesce(jsonb_agg(fs.sig ORDER BY fs.sig::text), '[]'::jsonb)
                FROM (
                  SELECT jsonb_build_object(
                    'properties',           cf.properties,
                    'invoice_display_name', cf.invoice_display_name,
                    'values', (
                      SELECT coalesce(
                        jsonb_agg(jsonb_build_array(bmf.key, to_jsonb(cfv.values)) ORDER BY bmf.key),
                        '[]'::jsonb
                      )
                      FROM charge_filter_values cfv
                      JOIN billable_metric_filters bmf ON bmf.id = cfv.billable_metric_filter_id
                      WHERE cfv.charge_filter_id = cf.id
                        AND cfv.deleted_at IS NULL
                        AND bmf.deleted_at IS NULL
                    )
                  ) AS sig
                  FROM charge_filters cf
                  WHERE cf.charge_id = c.id AND cf.deleted_at IS NULL
                ) fs
              )
            ) AS signature
          FROM charges c
          JOIN duplicate_groups dg ON dg.plan_id = c.plan_id AND dg.parent_id = c.parent_id
          WHERE c.deleted_at IS NULL
        ),
        duplicates AS (
          SELECT DISTINCT newer.id
          FROM signatures newer
          JOIN signatures older
            ON older.plan_id = newer.plan_id
            AND older.parent_id = newer.parent_id
            AND older.signature = newer.signature
            AND (older.created_at, older.id) < (newer.created_at, newer.id)
        ),
        deleted_charges AS (
          UPDATE charges SET deleted_at = NOW()
          WHERE id IN (SELECT id FROM duplicates)
          RETURNING id
        ),
        deleted_filters AS (
          UPDATE charge_filters SET deleted_at = NOW()
          WHERE deleted_at IS NULL
            AND charge_id IN (SELECT id FROM deleted_charges)
          RETURNING id
        )
        UPDATE charge_filter_values SET deleted_at = NOW()
        WHERE deleted_at IS NULL
          AND charge_filter_id IN (SELECT id FROM deleted_filters)
      SQL
    end
  end

  def down
  end
end
