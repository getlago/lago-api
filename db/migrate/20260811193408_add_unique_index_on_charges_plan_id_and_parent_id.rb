# frozen_string_literal: true

class AddUniqueIndexOnChargesPlanIdAndParentId < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  # NOTE: A parent charge must materialize at most once per child (overridden) plan.
  #       Exact duplicate copies are soft-deleted by the previous migration; copies that
  #       diverged in billing attributes cannot be resolved automatically — this migration
  #       fails with the remaining ids so an operator can pick the copy carrying the
  #       intended pricing and discard the others, then rerun db:migrate.
  def up
    remaining = select_rows(<<~SQL)
      SELECT plan_id, parent_id, string_agg(id::text, ', ' ORDER BY created_at)
      FROM charges
      WHERE parent_id IS NOT NULL AND deleted_at IS NULL
      GROUP BY plan_id, parent_id
      HAVING count(*) > 1
    SQL

    if remaining.any?
      details = remaining.map { |plan_id, parent_id, ids| "  plan #{plan_id}, parent charge #{parent_id}: charges #{ids}" }.join("\n")
      raise StandardError, <<~MSG
        Cannot add unique index on charges (plan_id, parent_id): #{remaining.size} child plan(s)
        still hold several charges for the same parent charge, and the copies differ in billing
        attributes, so no copy can be removed automatically.

        #{details}

        For each group, decide which charge carries the intended pricing, discard the others
        (e.g. in a Rails console: Charges::DestroyService.call(charge: Charge.find("<id>"))),
        then rerun the migrations.
      MSG
    end

    add_index :charges,
      [:plan_id, :parent_id],
      unique: true,
      where: "parent_id IS NOT NULL AND deleted_at IS NULL",
      algorithm: :concurrently,
      if_not_exists: true
  end

  def down
    remove_index :charges, [:plan_id, :parent_id], if_exists: true
  end
end
