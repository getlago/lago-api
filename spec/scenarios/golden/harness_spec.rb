# frozen_string_literal: true

require "rails_helper"

# Tests the HARNESS, not Lago.
#
# Everything else in spec/scenarios/golden asserts that Lago bills correctly. This file asserts that
# those assertions would notice if it did not — which is a different question, and the one that gets
# quietly answered "no" when a suite is edited by someone optimising for green.
#
# Two mechanisms:
#
#   AGREEMENT  schema.json and the interpreter must describe the same capabilities, in BOTH
#              directions. A schema that permits more than the runner implements lets a row assert
#              nothing; a runner that implements more than the schema permits means rows cannot
#              reach it. Capabilities are DERIVED from the runner's own dispatch, so the check
#              compares the schema against the code rather than against a second description of it.
#
#   CANARIES   rows engineered to fail, run for real. A weakened comparison, a skipped field or a
#              loosened lint all look locally reasonable and break no green row — and all of them
#              make a canary pass. A passing canary fails the build.
describe "Golden harness" do
  include GoldenRunner

  let(:organization) { create(:organization, webhook_url: nil) }

  def schema
    @schema ||= JSON.parse(File.read(GoldenMatrix.dir.join("schema.json")))
  end

  def schema_enum(*path)
    schema.dig("definitions", *path).fetch("enum").compact.map(&:to_s).sort
  end

  describe "schema and interpreter agree" do
    it "implements every timeline verb the schema permits, and permits every verb it implements" do
      expect(GoldenCapabilities.step_verbs).to match_array(schema_enum("step", "properties", "do")),
        "schema.json and GoldenRunner#perform_golden_step disagree on timeline verbs. A verb in the " \
        "schema but not the runner makes rows using it fail confusingly; a verb in the runner but " \
        "not the schema is unreachable."
    end

    it "implements every error stage the schema permits" do
      permitted = schema_enum("expectation", "properties", "error", "properties", "stage")
      unimplemented = permitted - GoldenCapabilities.error_stages

      expect(unimplemented).to be_empty,
        "schema.json permits expect.error.stage #{unimplemented.inspect}, which the interpreter does " \
        "not implement. A row using one would assert NOTHING and pass — see canary/unimplemented-error-stage."
    end

    it "implements every resource kind the schema permits" do
      expect(GoldenCapabilities.resource_kinds)
        .to match_array(schema_enum("resource_expectation", "properties", "kind"))
    end

    it "reads every top-level expectation the schema defines" do
      defined = schema.dig("definitions", "expectation", "properties").keys.sort
      expect(GoldenCapabilities.expectation_kinds).to match_array(defined),
        "an expectation the schema defines but the assertion phase never reads is a row that passes " \
        "while asserting nothing."
    end

    it "materialises every setup section the schema defines" do
      defined = schema.dig("definitions", "setup", "properties").keys.sort
      unused = defined - GoldenCapabilities.setup_keys

      expect(unused).to be_empty,
        "schema.json defines setup section(s) #{unused.inspect} that the interpreter never reads, so " \
        "a row configuring them would be silently ignored."
    end

    # The check above only looks at top-level sections, which leaves a section that is plainly read
    # but one of whose KEYS is not. Scoped per section rather than scanned over the whole runner,
    # because a literal borrowed from a neighbouring section satisfies the check by accident.
    it "reads every nested setup key the schema defines" do
      unread = GoldenCapabilities.unread_setup_keys(schema)

      expect(unread).to be_empty,
        "schema.json defines setup key(s) #{unread.inspect} that the interpreter never reads. A row " \
        "setting one is silently ignored and gets the default, which looks exactly like a row that " \
        "did not set it — either forward the key or remove it from the schema."
    end

    it "declares a source region for every setup section the schema defines" do
      sections = schema.dig("definitions", "setup", "properties").keys

      expect(sections - GoldenCapabilities::SETUP_SECTION_SOURCES.keys).to be_empty,
        "a new setup section needs an entry in GoldenCapabilities::SETUP_SECTION_SOURCES, or its " \
        "nested keys go unchecked — which is the whole bug class the check above exists for."
    end
  end

  describe "generated inventory" do
    # scenarios.json and the generated markdown are build products of `rake golden:docs`, not
    # committed files, so staleness cannot happen — what CAN break silently is the summary drifting
    # from the rows it claims to describe. This pins the one invariant that survives regeneration.
    it "describes every row on disk" do
      summary = JSON.parse(GoldenLedger.scenario_summary.to_json)

      expect(summary["generated_from_rows"]).to eq(GoldenMatrix.rows.size),
        "GoldenLedger.scenario_summary describes #{summary["generated_from_rows"]} rows while " \
        "#{GoldenMatrix.rows.size} are on disk — the inventory generator is dropping or inventing " \
        "scenarios."
    end
  end

  describe "denominator delta" do
    # The surveyor's question: which cells exist now that a recorded baseline has never seen. Answered
    # against recorded cell identities rather than counts, so the delta NAMES the new cells instead of
    # reporting that some number of them appeared somewhere.
    it "names the cells present now and absent in the snapshot" do
      snapshot = GoldenLedger.denominator_snapshot
      dropped = snapshot["B1"]["cells"].first
      trimmed = snapshot.merge("B1" => snapshot["B1"].merge("cells" => snapshot["B1"]["cells"].drop(1)))

      delta = GoldenLedger.denominator_delta(against: {"cells_by_block" => trimmed})

      expect(delta).to eq("B1" => [snapshot["B1"]["axes"].zip(dropped).to_h]),
        "a snapshot missing exactly one B1 cell must come back as exactly that cell, keyed by its " \
        "axis names — a delta that miscounts or renames here would misdirect the surveyor on every run."
    end

    it "counts every cell of a block the snapshot has never seen" do
      snapshot = GoldenLedger.denominator_snapshot
      delta = GoldenLedger.denominator_delta(against: {"cells_by_block" => snapshot.except("B21")})

      expect(delta.keys).to eq(["B21"])
      expect(delta["B21"].size).to eq(snapshot["B21"]["cells"].size),
        "a block absent from the baseline is new work in its entirety; reporting fewer cells than it " \
        "has means part of a new block would never be surveyed."
    end

    it "reports nothing when the snapshot matches the present" do
      delta = GoldenLedger.denominator_delta(against: {"cells_by_block" => GoldenLedger.denominator_snapshot})

      expect(delta).to eq({}),
        "an up-to-date baseline must produce an empty delta, or every daily run cries wolf: " \
        "#{delta.keys.inspect} reported as changed."
    end

    # The delta is only as good as the file it is computed against, so the committed baseline must
    # stay loadable and shaped like what denominator_delta expects.
    it "has a committed baseline the delta can be computed against" do
      baseline = YAML.safe_load_file(GoldenMatrix.dir.join("baseline.yml"), aliases: true)

      expect(baseline.keys).to include("sha", "recorded_at", "cells_by_block"),
        "baseline.yml must record sha, recorded_at and cells_by_block — rewrite it with `rake golden:baseline`."
      expect { GoldenLedger.denominator_delta(against: baseline) }.not_to raise_error
    end
  end

  describe "external coverage claims" do
    # An external mark tells a reader "somebody is watching this cell", so a stale or invented
    # reference is worse than no mark: it converts a real gap into an apparent one that is covered.
    let(:claims) { YAML.safe_load_file(GoldenMatrix.dir.join("external_coverage.yml"), aliases: true) }

    it "points at files and lines that exist" do
      broken = claims.filter_map do |claim|
        file, line = claim.fetch("covered_by").split(":")
        path = Rails.root.join(file)
        next "#{claim["block"]} #{claim["covered_by"]} — file does not exist" unless path.exist?

        count = path.readlines.size
        next if line.to_i.between?(1, count)
        "#{claim["block"]} #{claim["covered_by"]} — file has only #{count} lines"
      end

      expect(broken).to be_empty, "external coverage claims that no longer resolve:\n- #{broken.join("\n- ")}"
    end

    it "claims only cells that exist in their block" do
      unknown = claims.reject do |claim|
        block = GoldenLedger.block_by_id(claim.fetch("block"))
        block && GoldenLedger.expressible_cells(block).include?(claim.fetch("cell").transform_values(&:to_s))
      end

      expect(unknown).to be_empty,
        "external coverage claims a cell that is not in its block (an axis was renamed, or the cell " \
        "is illegal): #{unknown.map { |claim| "#{claim["block"]} #{claim["cell"]}" }.inspect}"
    end
  end

  describe "capability requirements" do
    # A requirement naming a kind the checker does not understand would raise mid-ledger; one naming a
    # nonsense VALUE would block its cells forever and silently. The first is caught here; the second
    # is why `rake golden:ledger` prints every blocked reason rather than only a count.
    def declared_requirements
      GoldenLedger.blocks.flat_map do |block|
        block_level = (block["requires"] || {}).to_a
        per_value = block["axes"].values.flat_map { |spec| (spec["requires"] || {}).values.flat_map(&:to_a) }
        (block_level + per_value).map { |kind, value| [block["id"], kind, value] }
      end
    end

    it "declares only requirement kinds the checker understands" do
      unknown = declared_requirements.reject { |_id, kind, _value| GoldenCapabilities::REQUIREMENT_KINDS.include?(kind) }

      expect(unknown).to be_empty,
        "blocks.yml declares requirement kind(s) the checker does not understand: " \
        "#{unknown.map { |id, kind, value| "#{id} #{kind}:#{value}" }.inspect}. " \
        "Known kinds: #{GoldenCapabilities::REQUIREMENT_KINDS.join(", ")}."
    end

    it "accounts for every legal cell as either writeable or blocked" do
      GoldenLedger.summary.each do |block|
        expect(block[:expressible] + block[:blocked]).to eq(block[:legal]),
          "#{block[:id]}: writeable (#{block[:expressible]}) + blocked (#{block[:blocked]}) does not " \
          "equal legal (#{block[:legal]}) — cells are being lost between the two counts."
      end
    end

    it "reports a reason for every blocked cell" do
      GoldenLedger.summary.reject { |block| block[:blocked].zero? }.each do |block|
        expect(block[:blocked_reasons].values.sum).to be >= block[:blocked],
          "#{block[:id]} has #{block[:blocked]} blocked cell(s) but reasons covering only " \
          "#{block[:blocked_reasons].values.sum}. A cell blocked for no stated reason is indistinguishable " \
          "from one quietly dropped from the denominator."
      end
    end
  end

  # A green run still has a backlog of pinned findings and characterization rows, so the suite reports
  # only what is NEW. A finding nobody signed off is the one worth reading.
  describe "findings ledger" do
    it "has an entry for every pinned finding" do
      new_findings = GoldenFindings.unacknowledged

      expect(new_findings).to be_empty,
        "#{new_findings.size} finding(s) are pinned by a row but absent from " \
        "#{GoldenFindings::LEDGER}:\n" +
          new_findings.map { |f| "  #{f["id"]} — #{f["rows"].join(", ")}\n      #{f["summary"]}" }.join("\n") +
          "\n\nA new finding is the one thing in a run worth reading, so it fails until somebody has. " \
          "Add it to the ledger with a status, or run `SEED=1 rake golden:triage` to rebuild the file."
    end

    it "notices when a known finding changes size" do
      moved = GoldenFindings.changed

      expect(moved).to be_empty,
        "#{moved.size} signed-off finding(s) now assert different numbers:\n" +
          moved.map { |f| "  #{f["id"]}  #{f["was"]} -> #{f["digest"]}  (#{f["rows"].join(", ")})" }.join("\n") +
          "\n\nEither it was partly fixed or it got worse. Re-read it and update the digest; accepting " \
          "new numbers silently is how a characterization row becomes a rubber stamp."
    end

    # Red pins are CI's allowlist of deliberate failures, so a typo here silently excuses a real
    # red. Rows may land in a later PR than the ledger, so absence from disk is legal — but a row
    # that IS on disk must look like a matrix row id, appear once, and not also claim to be a
    # passing characterization of the same defect.
    it "declares well-formed red pins" do
      reds = GoldenFindings.acknowledged.flat_map { |entry| Array(entry["red_pins"]) }
      on_disk = GoldenMatrix.rows.index_by { |row| row["id"] }

      problems = reds.tally.select { |_, count| count > 1 }.keys.map { |id| "#{id}: declared red by more than one finding" }
      problems += reds.reject { |id| id.match?(%r{\Ab\d+/\S+\z}) }.map { |id| "#{id.inspect}: not a row id" }
      problems += reds.filter_map do |id|
        "#{id}: is characterization: true — a row cannot be both pinned green and expected red" if on_disk[id]&.fetch("characterization", false)
      end

      expect(problems).to be_empty,
        "red_pins in #{GoldenFindings::LEDGER} have problems:\n  #{problems.join("\n  ")}"
    end
  end

  describe "canaries" do
    canaries = YAML.safe_load_file(
      Rails.root.join("spec/scenarios/golden/canaries/canaries.yml"),
      permitted_classes: [],
      aliases: true
    )

    it "has a canary for every assertion mechanism that can fail" do
      expect(canaries.size).to be >= 5
      expect(canaries.map { |c| c["guards"] }.uniq.size).to eq(canaries.size),
        "two canaries guard the same mechanism; one of them is not earning its runtime"
    end

    # Canaries bypass golden_spec's row runner, which is where `premium: true` becomes RSpec metadata.
    # Unhonoured here, a canary on a premium-gated mechanism would fail on the licence check rather
    # than on the assertion it exists to watch, and would count as working while guarding nothing.
    def run_canary(row)
      if row["premium"]
        lago_premium! { run_golden_row(row) }
      else
        run_golden_row(row)
      end
    end

    canaries.each do |canary|
      # aggregate_failures is enabled globally (spec_helper.rb), which RECORDS expectation failures
      # instead of raising them — so a canary run inside it would appear to pass and then explode on
      # `error.message`. Disabled here so the canary's failure is a real exception we can inspect.
      it "#{canary["id"]} fails — guards #{canary["guards"]}", aggregate_failures: false do
        error = nil
        begin
          run_canary(canary.fetch("row"))
        rescue StandardError, RSpec::Expectations::ExpectationNotMetError => e
          error = e
        end

        expect(error).not_to be_nil,
          "canary #{canary["id"]} PASSED. It is built to fail, so the mechanism it guards " \
          "(#{canary["guards"]}) has stopped working — a row can now assert this and be believed " \
          "when it should not be."

        expect(error.message).to include(canary.fetch("expect_failure")),
          "canary #{canary["id"]} failed, but for the wrong reason. Expected the failure to mention " \
          "#{canary.fetch("expect_failure").inspect} so that the mechanism under guard is the thing " \
          "that fired; got:\n#{error.message.lines.first(3).join}"
      end
    end
  end

  describe "lints fire" do
    # Each lint is exercised against a row built to trip it: a lint nobody has watched fail is a
    # comment.
    def lint_errors_for(row)
      allow(GoldenMatrix).to receive(:rows).and_return([row.merge("__file" => "canary.yml")])
      GoldenMatrix.lint_errors
    end

    let(:sound_row) do
      {
        "id" => "b01/lint/sound", "block" => "B1",
        "axes" => {"charge_model" => "standard", "aggregation" => "sum_agg", "observed_via" => "invoice", "events" => "one"},
        "provenance" => "canary", "runners" => ["rspec"],
        "setup" => {
          "metrics" => [{"code" => "m", "aggregation_type" => "sum_agg", "field_name" => "amount"}],
          "charges" => [{"billable_metric_code" => "m", "charge_model" => "standard"}]
        },
        "timeline" => [{"at" => "2024-03-01T00:00:00Z", "do" => "perform_billing"}],
        "expect" => {"invoices" => 1}
      }
    end

    it "accepts a sound row" do
      expect(lint_errors_for(sound_row)).to be_empty
    end

    it "catches a declared cell that contradicts the row's own setup" do
      row = sound_row.deep_dup
      row["axes"]["charge_model"] = "volume"

      expect(lint_errors_for(row).join).to include("axes.charge_model is \"volume\" but setup declares [\"standard\"]")
    end

    it "catches a row whose id does not name its own block" do
      row = sound_row.merge("id" => "b09/lint/wrong-block")
      expect(lint_errors_for(row).join).to include("id must start with")
    end

    it "catches a non-zero expectation with no math explaining it" do
      row = sound_row.deep_dup
      row["expect"]["invoice"] = {"total_amount_cents" => 3000}

      expect(lint_errors_for(row).join).to include("no `math` line")
    end

    it "catches a row that claims the live runner it cannot honour" do
      row = sound_row.merge("runners" => %w[rspec live], "calendar_sensitive" => true)
      expect(lint_errors_for(row).join).to include("cannot run live")
    end

    it "catches a probe row left behind after an investigation" do
      row = sound_row.merge("id" => "b01/probe/what-does-volume-do")
      expect(lint_errors_for(row).join).to include("must be deleted before finishing")
    end

    it "catches a multi-invoice expectation whose entries share a selector" do
      row = sound_row.deep_dup
      row["expect"]["invoice"] = [
        {"select" => {"invoice_type" => "subscription"}, "total_amount_cents" => 1000},
        {"select" => {"invoice_type" => "subscription"}, "total_amount_cents" => 2000}
      ]
      row["math"] = "lint fixture"

      expect(lint_errors_for(row).join).to include("appear twice")
    end

    it "catches a multi-invoice expectation with an unselected entry" do
      row = sound_row.deep_dup
      row["expect"]["invoice"] = [
        {"select" => {"index" => 0}, "total_amount_cents" => 1000},
        {"total_amount_cents" => 2000}
      ]
      row["math"] = "lint fixture"

      expect(lint_errors_for(row).join).to include("needs its own `select`")
    end

    it "catches a charge referencing a metric the row never declares" do
      row = sound_row.deep_dup
      row["setup"]["charges"] = [{"billable_metric_code" => "absent", "charge_model" => "standard"}]

      expect(lint_errors_for(row).join).to include("which the row does not declare")
    end
  end

  describe "surface vocabulary" do
    it "draws every surface-naming axis from one vocabulary" do
      expect(GoldenLedger.surface_vocabulary_errors).to be_empty
    end
  end
end
