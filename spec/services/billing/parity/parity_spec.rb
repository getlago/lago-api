# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("spec/services/billing/parity/parity_harness").to_s

# Differential test: the old engine (frozen under spec/legacy_engine) and the new one
# (app/services/billing) are driven over the same systematic space of inputs and every
# disagreement is classified.
#
# Two classifications are allowed to exist: INTENTIONAL, which must cite a line of the contract
# or of the characterisation, and OLD_ENGINE_BROKEN, which must name the mechanism that made the
# old output incoherent. NEW_ENGINE_SUSPECT and UNDECIDED are what this spec exists to surface,
# and the expectations below name every one that is known so that a new one fails the build.
#
# By default the run is a bounded, seeded subset that fits in CI. The full sweep is
#
#   LAGO_LICENSE_PATH=... lago exec -T -e BILLING_PARITY_FULL=1 api \
#     bundle exec rspec spec/services/billing/parity/parity_spec.rb
#
# which adds 6000 more sampled scenarios from the same seed, so a finding there is reproducible.
RSpec.describe "Billing date engine parity", type: :service do # rubocop:disable RSpec/DescribeClass -- the subject is the pair of engines, not one class
  # Everything is deterministic: the same seed, the same scenarios, the same verdict on every
  # machine and every run.
  subject(:report) { BillingParity.report(sample_size) }

  let(:sample_size) { ENV["BILLING_PARITY_FULL"] ? 6_000 : 250 }

  # The single open question this run raises: CONTRACT walk rule 7 makes `billing_at` a property
  # of the segment, so an arrears cycle cut by a rate change invoices the piece before the change
  # at the change rather than at the cycle close (R37/R45 keep it until the cycle closes). Rule 7
  # states the behaviour, but the contract's BUGS list - its register of deliberate divergences -
  # does not carry it, so it is escalated rather than accepted. See PARITY.md.
  let(:known_undecided) { ["an arrears slice cut off by a rate change falls due at the cut, not at the cycle close"] }

  # 1_090 scenarios: 768 core, 72 DST, 250 sampled. It was 1_930 (1_536 / 144 / 250) while the
  # space carried a `policy` axis; withdrawing `AnchorPolicy::Fixed` (LAGO-1766) halved the
  # systematic part of it, since the old engine can no longer be driven with
  # `realign_billing_anchor: false` for a comparison that has nothing to compare against.
  it "walks a large space of scenarios" do
    expect(report.scenario_count).to be >= 1_000
  end

  it "finds nothing the new engine looks wrong about" do
    suspects = report.divergences.select { it.classification == :NEW_ENGINE_SUSPECT }

    expect(suspects.map { "#{it.mechanism}\n#{it.detail}" }).to eq([])
  end

  it "raises no question beyond the one already recorded" do
    undecided = report.divergences.select { it.classification == :UNDECIDED }

    expect(undecided.map(&:mechanism).uniq - known_undecided).to eq([])
  end

  it "classifies every divergence" do
    expect(report.divergences.map(&:classification).uniq - %i[INTENTIONAL OLD_ENGINE_BROKEN UNDECIDED]).to eq([])
  end

  it "cites a contract or characterisation reference for every intentional divergence" do
    uncited = report.divergences.select { it.classification == :INTENTIONAL }
      .map(&:mechanism).uniq
      .reject { it.match?(/CONTRACT|\bR\d+\b|\bS\d+\b/) }

    expect(uncited).to eq([])
  end

  it "names a mechanism for every old-engine breakage" do
    unnamed = report.divergences.select { it.classification == :OLD_ENGINE_BROKEN }.select { it.mechanism.blank? }

    expect(unnamed).to eq([])
  end

  describe "invariants of the new engine, asserted without the old one" do
    it "holds every one of them" do
      violations = report.invariant_violations.map { |scenario, violation| "#{scenario.describe}\n  #{violation.rule}: #{violation.detail}" }

      expect(violations).to eq([])
    end
  end

  # A comparison that reports nothing is worthless whether or not the engine is correct, so the
  # comparison is itself tested: each mutation corrupts one field of the new engine's answer and
  # must come back as NEW_ENGINE_SUSPECT.
  describe "the comparison itself" do
    let(:mutations) do
      {
        "a window that ends an hour late" => ->(window) { window.with(ended_at: window.ended_at + 1.hour) },
        "a window that never came back" => nil,
        "a proration ratio nudged by 1/97" => ->(window) { window.with(proration_ratio: window.proration_ratio + Rational(1, 97)) },
        "a cycle that opened three hours early" => ->(window) { window.with(cycle_started_at: window.cycle_started_at - 3.hours) },
        "a segment billed ninety minutes late" => ->(window) { window.with(billing_at: window.billing_at + 90.minutes) },
        "a segment priced by the wrong rate" => ->(window) { window.with(rate_code: "bogus") }
      }
    end

    let(:clean_scenarios) do
      BillingParity::Space.core.select { it.timezone == "UTC" && it.timing == "advance" && it.ends_kind == :none }.first(12)
    end

    it "catches every corruption of the new engine's answer" do
      missed = mutations.reject { |_, mutate| catches?(mutate) }.keys

      expect(missed).to eq([])
    end

    def catches?(mutate)
      travel_to(BillingParity::FROZEN_NOW) do
        clean_scenarios.all? { |scenario| catches_in?(scenario, mutate) }
      end
    end

    def catches_in?(scenario, mutate)
      inputs = BillingParity::Inputs.new(scenario)
      runner = BillingParity::Runner.new(inputs)
      old_windows, new_windows, old_error, new_error = runner.run(:segments_overlapping)
      return true if new_windows.blank?
      return true if compare(scenario, inputs, runner, old_windows, new_windows, old_error, new_error).any? { it.classification == :NEW_ENGINE_SUSPECT }

      corrupted = mutate ? new_windows[0..-2] + [mutate.call(new_windows.last)] : new_windows[0..-2]
      compare(scenario, inputs, runner, old_windows, corrupted, old_error, new_error).any? { it.classification == :NEW_ENGINE_SUSPECT }
    end

    def compare(scenario, inputs, runner, old_windows, new_windows, old_error, new_error)
      BillingParity::Comparison.new(scenario, inputs, :segments_overlapping, old_windows, new_windows, old_error, new_error, runner:).divergences
    end
  end
end
