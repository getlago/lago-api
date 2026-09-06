# frozen_string_literal: true

# Three-way differential harness.
#
# Drives THREE implementations of the product-catalog billing date engine over the same
# inputs and classifies every disagreement by which pair agrees:
#
#   OLD  app/services/billing_periods/**, vendored verbatim at spec/legacy_engine
#   NEW  app/services/billing/**            (wired into all five call sites today)
#   PR   getlago/lago-api#6267 `engine-dates`, vendored at spec/pr_engine, plus the two
#        PARITY DELTA blocks marked in `spec/pr_engine/billing/rate_cards/schedule.rb`:
#        `Cycle#consumed_ratio`, which the PR had no equivalent for, and the fencepost in
#        `#cycles_overlapping`. Both were added for THIS comparison, not by the PR's
#        author, so that the two designs are judged on their design difference — the
#        per-CYCLE release gate, which is untouched — rather than on a missing capability.
#
# `parity_harness.rb` is loaded and NOT modified: its seed, its scenario space and its
# two-way verdicts stay byte-for-byte reproducible. This file adds a third driver, a
# three-way classifier and the QA plan as a named scenario set.
#
# Nothing here touches ActiveRecord. All three engines read the same handful of messages
# off their inputs, so the Structs `parity_harness.rb` already defines drive all three.

require Rails.root.join("spec/services/billing/parity/parity_harness").to_s

PR_ENGINE_ROOT = Rails.root.join("spec/pr_engine")
%w[
  billing/interval
  billing/calendar
  billing/segments
  billing/rate_cards/schedule
  billing/rate_cards/build_schedule_service
  subscription_rate_cards/resolve_rate_phases_service
].each { |file| require PR_ENGINE_ROOT.join(file).to_s }

module BillingParity
  module ThreeWay
    ENGINES = %i[old new pr].freeze

    CLASSIFICATIONS = %i[
      ALL_THREE_AGREE
      NEW_AND_PR_AGREE_OLD_DIFFERS
      OLD_AND_PR_AGREE_NEW_DIFFERS
      OLD_AND_NEW_AGREE_PR_DIFFERS
      ALL_THREE_DIFFER
    ].freeze

    # The end convention is the ONLY thing normalised. OLD closes a window on the last
    # instant it covers; NEW and PR close it on the first instant they do not. Adding one
    # nanosecond to OLD's close puts all three on the exclusive convention, and the 1 us
    # comparison absorbs the two shapes of "last instant" OLD produces (`.end_of_day` lands
    # on .999999999, `moment_before` on -1 us). The smallest real disagreement OLD can
    # produce is a whole second, so nothing real hides under it.
    #
    # Arrears `billing_at` IS the window's close, so it carries the same conversion. That
    # normalises away QA_ACCEPTANCE's BREAK 2 (the issuing date) by construction — it is a
    # presentation question about which instant names the day, not a date-layer answer.
    END_TOLERANCE = BillingParity::END_TOLERANCE
    RATIO_TOLERANCE = BillingParity::RATIO_TOLERANCE

    # What one engine answered: either a list of Windows, a scalar instant, or the reason
    # it could not answer. An engine that raises, wedges or truncates records that AS its
    # answer rather than taking the run down with it.
    Answer = Data.define(:windows, :scalar, :failure) do
      def failed? = !failure.nil?

      def to_s
        return "<#{failure}>" if failed?
        return scalar ? scalar.utc.strftime("%Y-%m-%d %H:%M:%S.%6N") : "nil" if windows.nil?
        return "<empty>" if windows.empty?

        windows.map { "    #{it}" }.join("\n")
      end
    end

    Verdict = Data.define(:scenario_id, :query, :classification, :mechanism, :answers, :describe) do
      def render
        [
          "### #{scenario_id} · #{query} · #{classification}",
          describe,
          "  mechanism: #{mechanism}",
          *ENGINES.map { |engine| "  #{engine.to_s.upcase}\n#{answers.fetch(engine)}" }
        ].join("\n")
      end
    end

    module_function

    def failure(reason) = Answer.new(windows: nil, scalar: nil, failure: reason)

    def windows(list) = Answer.new(windows: list, scalar: nil, failure: nil)

    def scalar(time) = Answer.new(windows: nil, scalar: time, failure: nil)

    # Two answers agree when they say the same thing about every field. An engine that
    # failed agrees only with another that failed the same way.
    def agree?(a, b, timing:)
      return a.failure == b.failure if a.failed? || b.failed?
      return scalars_agree?(a.scalar, b.scalar, timing:) if a.windows.nil? || b.windows.nil?
      return false unless a.windows.size == b.windows.size

      a.windows.zip(b.windows).all? { |left, right| window_agrees?(left, right) }
    end

    def window_agrees?(left, right)
      close?(left.started_at, right.started_at) &&
        close?(left.ended_at, right.ended_at) &&
        close?(left.cycle_started_at, right.cycle_started_at) &&
        left.cycle_index == right.cycle_index &&
        close?(left.billing_at, right.billing_at) &&
        left.rate_code == right.rate_code &&
        left.override_code == right.override_code &&
        ratio_close?(left.proration_ratio, right.proration_ratio)
    end

    # A scalar instant carries the same end convention: an arrears answer names the close
    # of a window, so OLD's inclusive close is allowed to match either way round.
    def scalars_agree?(a, b, timing:)
      return a == b if a.nil? || b.nil?
      return true if close?(a, b)
      return false unless timing == "arrears"

      close?(exclusive(a), b) || close?(a, exclusive(b))
    end

    def exclusive(time) = Time.zone.at(time.to_r + Rational(1, 1_000_000_000)).utc

    def close?(a, b)
      return a == b if a.nil? || b.nil?

      (a.to_r - b.to_r).abs <= END_TOLERANCE
    end

    def ratio_close?(a, b, tolerance = RATIO_TOLERANCE)
      (a.to_f - b.to_f).abs <= tolerance
    end

    def classify(answers, timing:)
      old_new = agree?(answers[:old], answers[:new], timing:)
      old_pr = agree?(answers[:old], answers[:pr], timing:)
      new_pr = agree?(answers[:new], answers[:pr], timing:)

      return :ALL_THREE_AGREE if old_new && old_pr && new_pr
      return :NEW_AND_PR_AGREE_OLD_DIFFERS if new_pr
      return :OLD_AND_PR_AGREE_NEW_DIFFERS if old_pr
      return :OLD_AND_NEW_AGREE_PR_DIFFERS if old_new

      :ALL_THREE_DIFFER
    end

    # The SHAPE of a disagreement, in a handful of words, so that thousands of verdicts can
    # be counted by cause instead of read one at a time. It describes what `b` says that `a`
    # does not; the caller passes the agreeing pair first and the odd one out second.
    def shape(a, b)
      return "#{a.failed? ? "a" : "b"} could not answer: #{a.failure || b.failure}" if a.failed? || b.failed?
      return "scalar instants differ" if a.windows.nil? || b.windows.nil?
      return "one list empty, the other #{[a.windows.size, b.windows.size].max} long" if a.windows.empty? ^ b.windows.empty?

      prefix = trailing_difference(a.windows, b.windows)
      return prefix if prefix

      first_field_difference(a.windows, b.windows)
    end

    # A list that is the other with windows added or dropped off the END is the commonest
    # shape by far — a walk that stopped sooner, a filter that kept one more cycle — and it
    # is worth naming as that rather than as "window 8 differs".
    def trailing_difference(a, b)
      return nil if a.size == b.size

      shorter, longer = (a.size < b.size) ? [a, b] : [b, a]
      return nil unless shorter.each_with_index.all? { |window, index| window_agrees?(window, longer[index]) }

      "#{(a.size < b.size) ? "the second" : "the first"} list carries #{(a.size - b.size).abs} more trailing window(s)"
    end

    FIELDS = %i[started_at ended_at cycle_started_at cycle_index billing_at rate_code override_code proration_ratio].freeze

    def first_field_difference(a, b)
      pairs = a.zip(b).reject { |left, right| right.nil? || window_agrees?(left, right) }
      left, right = pairs.first
      return "lists differ in length (#{a.size} vs #{b.size}) and in content" if left.nil?

      field = FIELDS.find { |name| !field_agrees?(left, right, name) }
      "#{field} differs (first at window #{a.index(left)})"
    end

    def field_agrees?(left, right, field)
      case field
      when :cycle_index, :rate_code, :override_code then left.public_send(field) == right.public_send(field)
      when :proration_ratio then ratio_close?(left.proration_ratio, right.proration_ratio)
      else close?(left.public_send(field), right.public_send(field))
      end
    end

    # What the minority says that the majority does not. For ALL_THREE_DIFFER both edges
    # are described, since there is no majority to measure against.
    def mechanism(classification, answers)
      case classification
      when :ALL_THREE_AGREE then nil
      when :NEW_AND_PR_AGREE_OLD_DIFFERS then "OLD: #{shape(answers[:new], answers[:old])}"
      when :OLD_AND_PR_AGREE_NEW_DIFFERS then "NEW: #{shape(answers[:old], answers[:new])}"
      when :OLD_AND_NEW_AGREE_PR_DIFFERS then "PR: #{shape(answers[:new], answers[:pr])}"
      else "OLD/NEW: #{shape(answers[:new], answers[:old])} | PR/NEW: #{shape(answers[:new], answers[:pr])}"
      end
    end

    # ---------------------------------------------------------------------------------
    # The PR engine, driven and normalised into the same Window shape as the other two
    # ---------------------------------------------------------------------------------
    #
    # PR::Schedule hands out CYCLES; the segments are asked of each cycle, and the fields
    # a billing_segments row carries are read off the pair exactly the way PR 6267's own
    # `build_schedule_service_legacy_parity_spec.rb` reads them.
    class PrDriver
      def initialize(anchor_date:, timezone:, starts_at:, ends_at:, timing:, prorated:, rates:, phases:, realign:)
        @rates = rates
        @schedule = PrEngine::Billing::RateCards::Schedule.new(
          anchor_date:,
          phases: pr_phases(phases),
          rates:,
          prorated:,
          realign_billing_anchor: realign,
          timezone:,
          starts_at:,
          ends_at:,
          timing:
        )
      end

      attr_reader :schedule, :rates

      # PR's BuildScheduleService appends `Phase.default` when every configured phase is
      # bounded, and PR's Schedule refuses an empty list. Both are the PR's own integration
      # rules, replayed here rather than worked around.
      def pr_phases(phases)
        configured = phases.map do |phase|
          PrEngine::Billing::RateCards::Schedule::Phase.new(
            position: phase.position,
            cycle_count: phase.billing_interval_cycle_count,
            code: phase.code,
            override: phase.rate_override
          )
        end

        return configured if configured.any? { |phase| phase.cycle_count.nil? }

        configured + [PrEngine::Billing::RateCards::Schedule::Phase.default]
      end

      def segments_overlapping(range) = flatten(schedule.cycles_overlapping(range))

      def segments_due_by(timestamp) = flatten(schedule.cycles_due_by(timestamp))

      # `due_after` is the analogue of NEW's `next_billing_at(after:)`: both answer "the
      # next instant anything falls due, strictly after this one". PR's method literally
      # NAMED `next_billing_at` answers a different question — the due instant of the cycle
      # currently running, which for an advance card is at or BEFORE the query instant —
      # and it is what PR wires into MaterializeService. Recorded separately.
      def due_after(timestamp) = schedule.due_after(timestamp)

      def next_billing_at(timestamp) = schedule.next_billing_at(timestamp)

      def flatten(cycles)
        cycles.flat_map do |cycle|
          cycle.segments(rates:).map do |segment|
            Window.new(
              started_at: segment.started_at.utc,
              ended_at: segment.ended_at.utc,
              cycle_started_at: cycle.started_at.utc,
              cycle_index: cycle.index,
              billing_at: cycle.billing_at(segment).utc,
              rate_code: segment.rate.code,
              override_code: cycle.phase.override&.code,
              proration_ratio: cycle.proration_ratio(segment)
            )
          end
        end
      end
    end

    # ---------------------------------------------------------------------------------
    # consumed_ratio, driven through all three
    # ---------------------------------------------------------------------------------
    #
    # The number `V2::Subscriptions::CreditUnusedAdvanceService` multiplies a paid advance
    # fee by: the share of a segment's cycle consumed at an instant, so that terminating
    # mid-cycle credits back the complement of it. All three engines are asked it here.
    #
    #   OLD  `Period#consumed_ratio`, computed as
    #        `boundaries_by_cycle[cycle].proration_ratio(period_from, range.end)` — from the
    #        segment's start, to the RANGE END, against the cycle's own ruler.
    #   NEW  `Billing::Schedule#consumed_ratio(segment:, at:)`.
    #   PR   `Cycle#consumed_ratio(segment, at)`, the PARITY DELTA added to the vendored
    #        engine for this comparison (it had no equivalent; PR 6267's own parity spec
    #        says so in writing).
    #
    # The instant asked about is the range end, because that is the one OLD baked in — it is
    # what "wherever the shipped engine produced one" means.
    #
    # Two engines can differ about the ratio, and they can differ about whether the question
    # is answerable at all: NEW and PR both REFUSE an `at` past the end of the window
    # containing the segment's start (an ArgumentError), where OLD's
    # `Boundaries#proration_ratio` caps at 1 and answers anyway. That is a domain
    # difference, not a ratio difference, and it is counted apart from one.
    # What NEW and PR say when the instant asked about lies outside the segment's own cycle.
    REFUSED = :refused

    Consumed = Data.define(:started_at, :cycle_index, :ratio) do
      def refused? = ratio == REFUSED

      # A ratio belongs to the window it was measured on, so pairing on the window is what
      # keeps one extra window in one list from misaligning every ratio after it.
      def key = [started_at.to_r, cycle_index]

      def to_s = "#{started_at.utc.strftime("%Y-%m-%d %H:%M:%S")}/c#{cycle_index} #{refused? ? "<refused>" : ratio}"
    end

    ConsumedSummary = Data.define(:compared, :ratio_disagreements, :domain_disagreements) do
      def disagreements = ratio_disagreements + domain_disagreements
    end

    module Consumption
      module_function

      def of_old(periods)
        periods.map do |period|
          Consumed.new(
            started_at: period.period_from.utc,
            cycle_index: period.cycle.index,
            ratio: period.consumed_ratio
          )
        end
      end

      def of_new(schedule, segments, at)
        segments.map do |segment|
          Consumed.new(
            started_at: segment.started_at.utc,
            cycle_index: segment.cycle_index,
            ratio: answer { schedule.consumed_ratio(segment:, at:) }
          )
        end
      end

      # PR hands out cycles, so the (cycle, segment) pair the call site holds is what the
      # question is asked of — the engine's own shape, not NEW's.
      def of_pr(cycles, rates, at)
        cycles.flat_map do |cycle|
          cycle.segments(rates:).map do |segment|
            Consumed.new(
              started_at: segment.started_at.utc,
              cycle_index: cycle.index,
              ratio: answer { cycle.consumed_ratio(segment, at) }
            )
          end
        end
      end

      # A refusal is an answer, recorded as one. Only NEW and PR can produce it: OLD's ratio
      # was computed while its periods were built and cannot raise here.
      def answer
        yield
      rescue ArgumentError
        REFUSED
      end

      def pairs(left, right)
        by_key = right.index_by(&:key)

        left.filter_map do |entry|
          other = by_key[entry.key]
          next if other.nil?

          [entry, other]
        end
      end

      def disagreement(a, b)
        return nil if a.refused? && b.refused?
        return :domain if a.refused? || b.refused?
        return nil if ThreeWay.ratio_close?(a.ratio, b.ratio)

        :ratio
      end

      # One pair of engines over a whole set of rows. `compared` is how many windows both
      # engines produced a ratio for, which is the population the disagreement counts are
      # out of; a ratio one engine produced for a window the other never emitted is not a
      # disagreement about consumed_ratio and is not counted as one.
      def summarise(rows, left, right)
        compared = 0
        ratios = []
        domains = []

        rows.each do |row|
          pairs(row.lists.fetch(left, []), row.lists.fetch(right, [])).each do |a, b|
            compared += 1
            detail = "#{row.scenario_id} #{row.timing} #{a} vs #{b}"

            case disagreement(a, b)
            when :ratio then ratios << detail
            when :domain then domains << detail
            end
          end
        end

        ConsumedSummary.new(compared:, ratio_disagreements: ratios, domain_disagreements: domains)
      end
    end

    # ---------------------------------------------------------------------------------
    # Running one scenario of the EXISTING matrix through all three
    # ---------------------------------------------------------------------------------
    class MatrixRun
      TIMEOUT = BillingParity::Runner::SCENARIO_TIMEOUT

      def initialize(scenario)
        @scenario = scenario
        @inputs = Inputs.new(scenario)
        @runner = Runner.new(@inputs)
      end

      attr_reader :scenario, :inputs, :runner

      def pr
        @pr ||= PrDriver.new(
          anchor_date: inputs.anchor_date,
          timezone: scenario.timezone,
          starts_at: inputs.started_at.utc,
          ends_at: inputs.ends_at,
          timing: scenario.timing,
          prorated: scenario.prorated,
          rates: inputs.rates,
          phases: inputs.phases,
          realign: true
        )
      end

      # The matrix's `walk_end` sits exactly on a cycle boundary, which turns every
      # difference between `<` and `<=` at the range end into a divergence. `:overlapping_mid`
      # asks the same question with the range ending an hour INSIDE a cycle, the way the
      # /cycles endpoint does (`end_on.end_of_day`), so a knife-edge convention can be told
      # apart from a real difference in which cycles an engine considers in range.
      QUERIES_3W = (QUERIES + [:overlapping_mid]).freeze

      def mid_range = inputs.walk_begin..(inputs.walk_end - 1.hour)

      def verdicts
        QUERIES_3W.filter_map do |query|
          next if inputs.terminating? && query != :segments_overlapping

          answers = ENGINES.index_with { |engine| answer_for(engine, query) }
          classification = ThreeWay.classify(answers, timing: scenario.timing)
          Verdict.new(
            scenario_id: scenario.id,
            query:,
            classification:,
            mechanism: ThreeWay.mechanism(classification, answers),
            answers:,
            describe: "  #{scenario.describe}"
          )
        end
      end

      def answer_for(engine, query)
        guarded do
          case [engine, query]
          in [:old, _] then old_answer(query)
          in [:new, :segments_overlapping] then ThreeWay.windows(runner.normalise_new(runner.schedule.segments_overlapping(runner.overlap_range)))
          in [:new, :segments_due_by] then ThreeWay.windows(runner.normalise_new(runner.schedule.segments_due_by(runner.due_by_at)))
          in [:new, :next_billing_at] then ThreeWay.scalar(runner.schedule.next_billing_at(after: inputs.midpoint))
          in [:pr, :segments_overlapping] then ThreeWay.windows(pr.segments_overlapping(runner.overlap_range))
          in [:pr, :segments_due_by] then ThreeWay.windows(pr.segments_due_by(runner.due_by_at))
          in [:pr, :next_billing_at] then ThreeWay.scalar(pr.due_after(inputs.midpoint))
          in [:new, :overlapping_mid] then ThreeWay.windows(runner.normalise_new(runner.schedule.segments_overlapping(mid_range)))
          in [:pr, :overlapping_mid] then ThreeWay.windows(pr.segments_overlapping(mid_range))
          end
        end
      end

      # No query in the matrix asks an EXCLUSIVE range, and OLD has no way to be asked one —
      # it snaps both ends of its range to whole UTC days. So the other half of the fencepost
      # fix, `Range#exclude_end?`, is asked of NEW and PR here directly rather than left as
      # an untested claim.
      def exclusive_range = inputs.walk_begin...(inputs.ends_at || inputs.walk_end)

      def exclusive_answers
        {
          new: guarded { ThreeWay.windows(runner.normalise_new(runner.schedule.segments_overlapping(exclusive_range))) },
          pr: guarded { ThreeWay.windows(pr.segments_overlapping(exclusive_range)) }
        }
      end

      # The consumed_ratio question, asked of all three engines about the windows of
      # `segments_overlapping` — the query the credit call site actually uses, over the same
      # range whose end OLD baked into its own `consumed_ratio`.
      def consumed
        ENGINES.index_with { |engine| consumed_list(engine) }
      end

      def consumed_at = runner.overlap_range.end

      # An engine that cannot walk contributes no ratios rather than taking the run down:
      # OLD wedges on non-UTC arrears (R26) and that is its answer here too.
      def consumed_list(engine)
        Timeout.timeout(TIMEOUT) { consumed_for(engine) }
      rescue Exception # rubocop:disable Lint/RescueException
        []
      end

      def consumed_for(engine)
        case engine
        when :old
          Consumption.of_old(
            runner.legacy(range: runner.overlap_range, exclude_out_of_range: false, termination: inputs.terminating?).periods
          )
        when :new
          Consumption.of_new(runner.schedule, runner.schedule.segments_overlapping(runner.overlap_range), consumed_at)
        when :pr
          Consumption.of_pr(pr.schedule.cycles_overlapping(runner.overlap_range), pr.rates, consumed_at)
        end
      end

      def old_answer(query)
        if query == :overlapping_mid
          return ThreeWay.windows(
            runner.normalise_old(runner.legacy(range: mid_range, exclude_out_of_range: false, termination: false).periods)
          )
        end

        result = runner.old_for(query)
        (query == :next_billing_at) ? ThreeWay.scalar(result) : ThreeWay.windows(result)
      end

      # Every engine gets the same cap. OLD is known to wedge on non-UTC arrears (R26), and
      # a wedge is its answer, not a reason to lose the run.
      def guarded
        Timeout.timeout(TIMEOUT) { yield }
      rescue Timeout::Error
        ThreeWay.failure("did not terminate within #{TIMEOUT}s")
      rescue Exception => e # rubocop:disable Lint/RescueException
        ThreeWay.failure("#{e.class}: #{e.message}")
      end
    end

    # The consumed ratios one scenario produced, one list per engine.
    ConsumedRow = Data.define(:scenario_id, :timing, :lists)

    Report = Data.define(:verdicts, :scenario_count, :consumed_rows) do
      def by_classification
        verdicts.group_by(&:classification).transform_values(&:size)
      end

      # consumed_ratio over the whole run, for one pair of engines.
      def consumed(left, right) = Consumption.summarise(consumed_rows, left, right)

      # Counted by cause: a classification with one mechanism behind it is one finding,
      # however many scenarios reach it.
      def by_mechanism(classification)
        of(classification).group_by(&:mechanism).transform_values(&:size).sort_by { -it.last }
      end

      def of(classification) = verdicts.select { it.classification == classification }
    end

    def run(scenarios)
      verdicts = []
      consumed_rows = []

      BillingParity.travel_to(FROZEN_NOW) do
        scenarios.each do |scenario|
          run = MatrixRun.new(scenario)
          verdicts.concat(run.verdicts)
          consumed_rows << ConsumedRow.new(scenario_id: scenario.id, timing: scenario.timing, lists: run.consumed)
        rescue Exception => e # rubocop:disable Lint/RescueException
          verdicts << Verdict.new(
            scenario_id: scenario.id, query: :harness, classification: :ALL_THREE_DIFFER,
            mechanism: "the harness itself failed",
            answers: ENGINES.index_with { ThreeWay.failure("harness: #{e.class}: #{e.message}") },
            describe: "  #{scenario.describe}"
          )
        end
      end

      Report.new(verdicts:, scenario_count: scenarios.size, consumed_rows:)
    end

    # ---------------------------------------------------------------------------------
    # consumed_ratio on the QA plan's own cases
    # ---------------------------------------------------------------------------------
    #
    # `QaPlanSet::Run` already builds all three engines from a case, and `qa_plan_set.rb` is
    # left untouched: only OLD has to be driven a second time here, because `consumed_ratio`
    # is a field of `Period` that the normalised `Window` the QA report compares does not
    # carry. The legacy service is handed exactly the flags `Run#old_answer` hands it.
    module QaConsumption
      module_function

      ROWS = Concurrent::Map.new

      def rows
        ROWS.fetch_or_store(:qa) { build }
      end

      def build
        BillingParity.travel_to(FROZEN_NOW) do
          BillingParity::QaPlanSet::CASES.map do |kase|
            ConsumedRow.new(scenario_id: kase.id, timing: kase.timing, lists: of(kase))
          end
        end
      end

      def of(kase)
        run = BillingParity::QaPlanSet::Run.new(kase)

        {
          old: Consumption.of_old(old_periods(run)),
          new: Consumption.of_new(run.new_schedule, new_segments(run), kase.to),
          pr: Consumption.of_pr(pr_cycles(run), run.pr_driver.rates, kase.to)
        }
      end

      def new_segments(run)
        case run.kase.query
        when :due_by then run.new_schedule.segments_due_by(run.kase.to)
        when :overlapping then run.new_schedule.segments_overlapping(run.kase.from..run.kase.to)
        end
      end

      def pr_cycles(run)
        case run.kase.query
        when :due_by then run.pr_driver.schedule.cycles_due_by(run.kase.to)
        when :overlapping then run.pr_driver.schedule.cycles_overlapping(run.kase.from..run.kase.to)
        end
      end

      def old_periods(run)
        kase = run.kase

        LegacyEngine::BillingPeriods::DatesService.from_subscription_rate_card(
          run.subscription_rate_card,
          rates: run.rates,
          range: kase.from..kase.to,
          rate_phases: LegacyEngine::SubscriptionRateCards::ResolveRatePhasesService::RatePhases.new(phases: run.phases),
          options: LegacyEngine::BillingPeriods::DatesService::Options.new(
            timezone: kase.timezone,
            exclude_out_of_range: kase.query == :due_by,
            realign_billing_anchor: true,
            termination: !kase.ends_at.nil?
          )
        ).periods
      end

      def summary(left, right) = Consumption.summarise(rows, left, right)
    end

    REPORTS = Concurrent::Map.new

    def report(sample_size)
      REPORTS.fetch_or_store(sample_size) do
        run(Space.core + Space.dst + Space.sampled(sample_size))
      end
    end
  end
end
