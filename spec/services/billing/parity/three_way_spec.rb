# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("spec/services/billing/parity/three_way_harness").to_s
require Rails.root.join("spec/services/billing/parity/qa_plan_set").to_s

# Three-way differential test.
#
#   OLD  the engine that shipped        spec/legacy_engine  (LegacyEngine::)
#   NEW  the engine wired in today      app/services/billing
#   PR   getlago/lago-api#6267          spec/pr_engine      (PrEngine::)
#
# The vendored PR engine carries TWO additions that are not PR 6267's, both marked
# `PARITY DELTA` in `spec/pr_engine/billing/rate_cards/schedule.rb` and both measured here:
#
#   1. `Cycle#consumed_ratio(segment, at)` — the capability the PR's own parity spec records
#      as missing, without which the PR cannot serve `CreditUnusedAdvanceService` and the
#      comparison would be arguing about a hole instead of about a design.
#   2. the fencepost in `#cycles_overlapping` — 183 verdicts in the full sweep where PR
#      dropped a window OLD and NEW both keep, and where the PR's class disagreed with
#      itself (`cycles_due_by` releases the same cycle at the same instant).
#
# What was deliberately NOT touched is the per-CYCLE release gate in `#walk_from`. That is
# the real design difference (`PARITY.md` U1) and the whole point of the comparison, so its
# size is pinned below and must not move.
#
# All three are driven over the same seeded scenario space and over the QA acceptance plan,
# and every disagreement is classified by which pair agrees. `parity_harness.rb` is loaded
# unmodified, so seed 20260904 still means exactly what the two-way run says it means.
#
# The committed run is the same bounded subset the two-way spec uses. The full sweep is
#
#   LAGO_LICENSE_PATH=... lago exec -T -e BILLING_PARITY_FULL=1 api \
#     bundle exec rspec spec/services/billing/parity/three_way_spec.rb
#
# which adds 6000 more sampled scenarios from the same seed. Findings: THREE_WAY.md.
RSpec.describe "Billing date engine three-way" do # rubocop:disable RSpec/DescribeClass -- the subject is three engines, not one class
  subject(:report) { BillingParity::ThreeWay.report(sample_size) }

  let(:full_sweep) { ENV["BILLING_PARITY_FULL"].present? }

  let(:sample_size) { full_sweep ? 6_000 : 250 }

  # PR's list being the leading part of NEW's is what "the same walk, released later" looks
  # like. Every PR-vs-NEW disagreement in either run has this shape, which is what makes it
  # one mechanism rather than a family of unrelated differences.
  def prefix_of?(shorter, longer)
    shorter.each_with_index.all? { |window, index| BillingParity::ThreeWay.window_agrees?(window, longer[index]) }
  end

  it "walks the same space the two-way run walks" do
    expect(report.scenario_count).to be >= 1_000
  end

  # The classification counts are the run's own headline, and both the committed subset and
  # the full sweep are quoted in THREE_WAY.md. Emitting them from the run itself means a
  # before/after comparison is read off the build rather than recomputed by hand.
  it "reports its classification counts" do
    warn "\n#{full_sweep ? "FULL SWEEP" : "COMMITTED"}: " \
         "#{report.scenario_count} scenarios, #{report.verdicts.size} verdicts"
    BillingParity::ThreeWay::CLASSIFICATIONS.each do |classification|
      warn "  #{classification}: #{report.of(classification).size}"
    end

    expect(report.verdicts.size).to be_positive
  end

  it "classifies every verdict" do
    expect(report.by_classification.keys - BillingParity::ThreeWay::CLASSIFICATIONS).to eq([])
  end

  # Every number here was re-measured when `AnchorPolicy::Fixed` was withdrawn (LAGO-1766) and
  # the `policy` axis left the space with it: 1_090 scenarios instead of 1_930, so roughly half
  # of every class. It was
  #   1_497 / 2_375 / 844 / 136 / 0
  # over the two-policy space, and before that — before the fencepost PARITY DELTA —
  #   1_392 / 2_162 / 1_057 / 136 / 105.
  # Closing the fencepost had moved all 105 `OLD_AND_NEW_AGREE_PR_DIFFERS` into
  # `ALL_THREE_AGREE` and 213 `ALL_THREE_DIFFER` into `NEW_AND_PR_AGREE_OLD_DIFFERS`; dropping
  # the axis moved nothing between classes, it only stopped asking half the questions.
  it "reproduces the committed counts exactly" do
    skip "the full sweep has its own counts, recorded in THREE_WAY.md" if full_sweep

    expect(report.by_classification).to eq(
      ALL_THREE_AGREE: 854,
      NEW_AND_PR_AGREE_OLD_DIFFERS: 1_279,
      ALL_THREE_DIFFER: 444,
      OLD_AND_PR_AGREE_NEW_DIFFERS: 70
    )
  end

  # The finding that matters most: the PR siding with the engine that shipped against the
  # one wired in today. One mechanism is behind all of them — OLD and PR both decide whether
  # to hand out a window per CYCLE (OLD through `cycle_due?`, R45/R46; PR through
  # `cycles_due_by`'s `if cycle.due_at > timestamp then break`), while NEW decides per
  # SEGMENT. In arrears that withholds two things: the cycle in progress, and the slice
  # before a mid-cycle rate change. A verdict here that is NOT NEW handing out strictly more
  # of the same walk is a second mechanism, and a new finding.
  describe "OLD_AND_PR_AGREE, NEW_DIFFERS" do
    let(:verdicts) { report.of(:OLD_AND_PR_AGREE_NEW_DIFFERS) }

    it "happens only on arrears cards" do
      expect(verdicts.map { it.describe[/timing=\w+/] }.uniq).to eq(["timing=arrears"])
    end

    it "is always NEW releasing more of the same walk, never a different walk" do
      not_a_prefix = verdicts.reject do |verdict|
        prefix_of?(verdict.answers[:pr].windows, verdict.answers[:new].windows)
      end

      expect(not_a_prefix.map { "#{it.scenario_id} #{it.query}" }).to eq([])
    end
  end

  # PR alone dropping a window used to happen wherever a cycle opened EXACTLY on the range
  # end: the vendored `cycles_overlapping` tested `cycle.started_at < range.end` where OLD's
  # `cycle_due?` and NEW's `overlaps?` both test "at or before", and it ignored
  # `Range#exclude_end?`. It was also inconsistent inside the PR's own class — `cycles_due_by`
  # releases the cycle whose `due_at` equals the timestamp, which for advance IS `started_at`,
  # and `cycles_overlapping` filtered that same cycle back out.
  #
  # 183 verdicts in the full sweep (105 committed) when it was last non-empty — both figures
  # measured over the two-policy space — advance only, `segments_overlapping` only. The PARITY DELTA in `spec/pr_engine/billing/rate_cards/schedule.rb` closes it, so
  # the class is now EMPTY: there is no query, no timing and no scenario left in which PR
  # alone drops a window.
  describe "OLD_AND_NEW_AGREE, PR_DIFFERS" do
    let(:verdicts) { report.of(:OLD_AND_NEW_AGREE_PR_DIFFERS) }

    it "no longer happens at all: the fencepost is closed" do
      expect(verdicts.map { "#{it.scenario_id} #{it.query}: #{it.mechanism}" }).to eq([])
    end
  end

  # The release gate. `PARITY.md` U1 is the one thing the two designs really disagree about:
  # OLD and PR gate release per CYCLE, NEW per SEGMENT. Its size is the decision the owner
  # has to make, and neither parity fix is allowed to move it — the consumed_ratio addition
  # answers a new question and the fencepost fix is advance-only, while every verdict in this
  # class is arrears. A change here means the gate itself moved and the comparison is no
  # longer measuring what it says it measures.
  #
  # The two numbers were 371 / 136 while the space carried a `policy` axis. Withdrawing
  # `AnchorPolicy::Fixed` (LAGO-1766) removed the fixed-anchor half of the space, which is why
  # they fell: the gate is unchanged per scenario, there are simply half as many scenarios.
  it "leaves the release gate exactly where it was before the two parity fixes" do
    expect(report.by_classification.fetch(:OLD_AND_PR_AGREE_NEW_DIFFERS)).to eq(full_sweep ? 339 : 70)
  end

  # The other half of the fencepost fix. An inclusive `a..b` asks about the instant `b`; an
  # exclusive `a...b` stops short of it, so the exclusive answer must be exactly the
  # inclusive one minus whatever opens at or after `b`. Asked of both engines over the core
  # space, because no query in the matrix uses an exclusive range and OLD cannot be asked one
  # at all — it snaps both ends of its range to whole UTC days.
  #
  # This is a statement about each engine on its own, not about the two agreeing: NEW and PR
  # still part company on an exclusive range wherever the release gate parts them, and that
  # is measured as such in the example below rather than folded in here.
  it "stops short of an exclusive range end, in NEW and PR alike" do
    findings = []

    BillingParity.travel_to(BillingParity::FROZEN_NOW) do
      BillingParity::Space.core.each do |scenario|
        run = BillingParity::ThreeWay::MatrixRun.new(scenario)
        boundary = run.exclusive_range.end
        exclusive = run.exclusive_answers

        %i[new pr].each do |engine|
          expected = run.answer_for(engine, :segments_overlapping).windows.reject { it.started_at >= boundary }
          got = exclusive.fetch(engine).windows

          next if got.size == expected.size &&
            got.zip(expected).all? { |a, b| BillingParity::ThreeWay.window_agrees?(a, b) }

          findings << "#{scenario.id} #{engine}: #{got.size} windows for a...b, expected #{expected.size}"
        end
      end
    end

    expect(findings.first(10)).to eq([])
  end

  # An exclusive range is a fresh question, so it gets the same test the inclusive ones get:
  # whenever NEW and PR differ, PR's list is the leading part of NEW's. If the fencepost fix
  # had over-reached, PR would carry a window NEW does not and this would fail; what it
  # actually finds is the release gate, arrears only, exactly as on an inclusive range.
  it "still answers an exclusive range with a leading part of what NEW answers" do
    diverged = []

    BillingParity.travel_to(BillingParity::FROZEN_NOW) do
      BillingParity::Space.core.each do |scenario|
        answers = BillingParity::ThreeWay::MatrixRun.new(scenario).exclusive_answers
        next if BillingParity::ThreeWay.agree?(answers.fetch(:new), answers.fetch(:pr), timing: scenario.timing)
        next if prefix_of?(answers.fetch(:pr).windows, answers.fetch(:new).windows)

        diverged << "#{scenario.id} (#{scenario.timing}): PR is not a prefix of NEW on a...b"
      end
    end

    expect(diverged.first(10)).to eq([])
  end

  # ---------------------------------------------------------------------------------------
  # consumed_ratio
  # ---------------------------------------------------------------------------------------
  #
  # `V2::Subscriptions::CreditUnusedAdvanceService` multiplies a paid advance fee by
  # `1 - consumed_ratio`, so this is the number a wrong answer bills a customer for. OLD
  # carried one on every Period; NEW has `Schedule#consumed_ratio(segment:, at:)`; the PR had
  # nothing, and the PARITY DELTA gives it `Cycle#consumed_ratio(segment, at)` in its own
  # shape. All three are asked about the same instant — the range end, which is the one OLD
  # baked into its own answer.
  describe "consumed_ratio" do
    it "compares it across all three engines wherever the shipped engine produced one" do
      new_pr = report.consumed(:new, :pr)
      new_old = report.consumed(:new, :old)

      warn "\nconsumed_ratio (#{full_sweep ? "FULL SWEEP" : "COMMITTED"}):"
      warn "  NEW/PR  compared #{new_pr.compared}, ratio #{new_pr.ratio_disagreements.size}, " \
           "domain #{new_pr.domain_disagreements.size}"
      warn "  NEW/OLD compared #{new_old.compared}, ratio #{new_old.ratio_disagreements.size}, " \
           "domain #{new_old.domain_disagreements.size}"

      expect(new_pr.compared).to be >= 1_000
    end

    it "finds NEW and PR agreeing on every window both produce" do
      summary = report.consumed(:new, :pr)

      expect(summary.disagreements.first(10)).to eq([])
    end

    # OLD answers the question outside the segment's cycle too, because
    # `Boundaries#proration_ratio` caps at 1 instead of refusing; NEW and PR both raise. That
    # is a difference about the DOMAIN of the question rather than about a ratio, and it is
    # the shape of nearly every OLD disagreement here, so it is measured as its own thing.
    it "records OLD answering outside the segment's cycle where both new engines refuse" do
      summary = report.consumed(:new, :old)

      expect(summary.domain_disagreements.size).to be_positive
    end

    # A share of a cycle cannot exceed the cycle. Asserted on the two engines that refuse a
    # question outside the segment's cycle rather than capping it: OLD's cap is what keeps
    # its own answer inside the bounds, which is not the same property.
    it "never lets NEW's or PR's ratio out of [0, 1]" do
      out_of_range = report.consumed_rows.flat_map do |row|
        row.lists.slice(:new, :pr).flat_map do |engine, list|
          list.filter_map do |entry|
            next if entry.refused? || entry.ratio.between?(0, 1)

            "#{row.scenario_id} #{engine}: #{entry}"
          end
        end
      end

      expect(out_of_range.first(10)).to eq([])
    end
  end

  # The strongest single statement this run supports: across every query and every scenario,
  # PR never says anything NEW does not — it only says less of it. Whenever the two differ,
  # PR's list is the leading part of NEW's, window for window and field for field. So the
  # whole PR/NEW gap is about WHEN a segment is handed out, never about what it says.
  it "always answers with a leading part of what NEW answers, never something different" do
    diverged = report.verdicts.reject do |verdict|
      new_answer = verdict.answers[:new]
      pr_answer = verdict.answers[:pr]
      next true if new_answer.failed? || pr_answer.failed? || new_answer.windows.nil? || pr_answer.windows.nil?

      prefix_of?(pr_answer.windows, new_answer.windows)
    end

    expect(diverged.map { "#{it.scenario_id} #{it.query}: #{it.mechanism}" }).to eq([])
  end

  # CONTRACT BUGS 4 is about money adding up, not about representation, so the invariant is
  # what has to be measured: the pieces of a cut cycle summing to exactly the cycle. NEW
  # asserts it as `Rational == 1`. This asks whether PR's `fdiv` ever fails the same test on
  # the same cut — measured, not assumed.
  it "sums a cut cycle to exactly 1 in Float wherever NEW does in Rational" do
    drifted = report.verdicts.flat_map do |verdict|
      new_answer = verdict.answers[:new]
      pr_answer = verdict.answers[:pr]
      next [] if new_answer.failed? || pr_answer.failed? || new_answer.windows.nil? || pr_answer.windows.nil?

      pr_cycles = pr_answer.windows.group_by(&:cycle_index)
      new_answer.windows.group_by(&:cycle_index).filter_map do |index, group|
        pr_group = pr_cycles[index]
        next if pr_group.nil? || pr_group.size != group.size || group.size < 2
        next unless group.sum(&:proration_ratio) == 1
        next if pr_group.sum(&:proration_ratio) == 1.0 # rubocop:disable Lint/FloatComparison -- exactness IS the question

        "#{verdict.scenario_id} cycle #{index}: #{pr_group.sum(&:proration_ratio).inspect}"
      end
    end

    expect(drifted).to eq([])
  end

  it "finds no disagreement at all between NEW and PR on the next billing instant" do
    disagreements = report.verdicts.select do |verdict|
      verdict.query == :next_billing_at &&
        !BillingParity::ThreeWay.agree?(verdict.answers[:new], verdict.answers[:pr], timing: "arrears")
    end

    expect(disagreements.map(&:scenario_id)).to eq([])
  end

  # BUGS 4 in CONTRACT.md: PR keeps `fdiv`, NEW moved to `Rational`. The two-way run found
  # no divergence from it in 7,680 scenarios; this asserts the same across a third engine,
  # comparing the two representations EXACTLY rather than within a tolerance.
  it "finds no proration ratio where Float and Rational disagree" do
    mismatched = report.verdicts.flat_map do |verdict|
      new_answer = verdict.answers[:new]
      pr_answer = verdict.answers[:pr]
      next [] if new_answer.failed? || pr_answer.failed? || new_answer.windows.nil? || pr_answer.windows.nil?

      new_answer.windows.zip(pr_answer.windows).filter_map do |a, b|
        next if b.nil? || a.proration_ratio == b.proration_ratio

        "#{verdict.scenario_id} #{a.proration_ratio} vs #{b.proration_ratio}"
      end
    end

    expect(mismatched).to eq([])
  end

  # The QA acceptance plan, encoded at the date layer so all three can be asked its
  # questions. It outranks all three engines: it is what product signed off against.
  describe "the QA plan as a named scenario set" do
    subject(:qa) { BillingParity::QaPlanSet.report }

    it "drives every encoded case through all three engines" do
      expect(qa.rows.size).to eq(BillingParity::QaPlanSet::CASES.size)
    end

    it "leaves unscored only the cases the plan itself left open" do
      expect(qa.open_rows.map { it.kase.id }).to match_array(%w[R3b-mid X1p])
    end

    %i[old new pr].each do |engine|
      it "has #{engine.to_s.upcase} matching the record on every case the plan pins" do
        broken = qa.broken(engine).map { |row| "#{row.kase.id}: #{row.details.fetch(engine).join("; ")}" }

        expect(broken).to eq([])
      end
    end

    # The plan's own cases asked the consumed_ratio question, at the instant each case's
    # window ends. X1p and X1f are the interesting ones: a termination mid-cycle is exactly
    # what `CreditUnusedAdvanceService` credits against, and they are where OLD's ceil'd
    # `billed_days` (CONTRACT BUGS 2) shows up in this number too.
    describe "consumed_ratio" do
      it "compares it across all three engines on the plan's cases" do
        new_pr = BillingParity::ThreeWay::QaConsumption.summary(:new, :pr)
        new_old = BillingParity::ThreeWay::QaConsumption.summary(:new, :old)

        warn "\nconsumed_ratio (QA PLAN):"
        warn "  NEW/PR  compared #{new_pr.compared}, ratio #{new_pr.ratio_disagreements.size}, " \
             "domain #{new_pr.domain_disagreements.size}"
        warn "  NEW/OLD compared #{new_old.compared}, ratio #{new_old.ratio_disagreements.size}, " \
             "domain #{new_old.domain_disagreements.size}"
        new_old.ratio_disagreements.each { warn "    #{it}" }

        expect(new_pr.compared).to be_positive
      end

      it "has PR agreeing with NEW on every case" do
        summary = BillingParity::ThreeWay::QaConsumption.summary(:new, :pr)

        expect(summary.disagreements).to eq([])
      end

      # The termination case the credit service exists for, written out in full rather than
      # counted: a card ending Sep 25 inside the cycle running Sep 10 -> Oct 10 has consumed
      # 15 of its 30 days. OLD's 16/30 here is the same ceil'd day count that makes X1p an
      # OPEN case on proration_ratio; NEW and PR both read the termination day as exclusive.
      it "credits half of the terminated cycle back on the plan's X1p card" do
        ratios = BillingParity::ThreeWay::QaConsumption.rows
          .find { it.scenario_id == "X1p" }
          .lists
          .transform_values { |list| list.last.ratio }

        expect(ratios[:new]).to eq(Rational(15, 30))
        expect(ratios[:pr]).to eq(15.fdiv(30))
        expect(ratios[:old]).to eq(16.fdiv(30))
      end
    end
  end
end
