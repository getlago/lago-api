# frozen_string_literal: true

require "rails_helper"

RSpec.describe "NOT VALID constraints" do # rubocop:disable RSpec/DescribeClass
  let(:structure_sql) { Rails.root.join("db/structure.sql").read }
  let(:allowlist) { YAML.load_file(Rails.root.join("db/not_valid_constraints.yml"), permitted_classes: [Date]) || [] }

  let(:not_valid_constraints) do
    structure_sql
      .scan(/ALTER TABLE (?:ONLY )?public\.(\w+)\n\s+ADD CONSTRAINT (\w+) [^;]+ NOT VALID;/)
      .map { |table, constraint| {"table" => table, "constraint" => constraint} }
  end

  it "only contains NOT VALID constraints registered in db/not_valid_constraints.yml" do
    registered = allowlist.map { |entry| entry.slice("table", "constraint") }
    unregistered = not_valid_constraints - registered

    expect(unregistered).to be_empty, <<~MSG
      The following constraints are NOT VALID but are not registered in db/not_valid_constraints.yml:

      #{unregistered.map { |c| "  - #{c["table"]}.#{c["constraint"]}" }.join("\n")}

      A NOT VALID constraint must be validated by a follow-up migration
      (`validate_foreign_key` or `validate_check_constraint`), normally added
      right after it in the same PR. If validation is not possible yet (e.g.
      existing rows must be backfilled or fixed first), register the constraint
      in db/not_valid_constraints.yml with a `validate_by` deadline.

      Note: when a table has several foreign keys to the same table, pass the
      `column:` option to `validate_foreign_key`, otherwise the wrong constraint
      may be validated silently.
    MSG
  end

  it "does not register constraints that are already validated" do
    registered = allowlist.map { |entry| entry.slice("table", "constraint") }
    stale = registered - not_valid_constraints

    expect(stale).to be_empty, <<~MSG
      The following db/not_valid_constraints.yml entries no longer match a NOT VALID
      constraint in db/structure.sql. They were validated (or removed): delete them
      from the registry.

      #{stale.map { |c| "  - #{c["table"]}.#{c["constraint"]}" }.join("\n")}
    MSG
  end

  it "validates registered constraints before their deadline" do
    overdue = allowlist.select { |entry| Date.parse(entry.fetch("validate_by").to_s) < Date.current }

    expect(overdue).to be_empty, <<~MSG
      The following NOT VALID constraints are past their validation deadline.
      Add a migration validating them, then remove them from
      db/not_valid_constraints.yml:

      #{overdue.map { |c| "  - #{c["table"]}.#{c["constraint"]} (validate_by: #{c["validate_by"]})" }.join("\n")}
    MSG
  end
end
