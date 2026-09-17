# frozen_string_literal: true

require "rails_helper"

RSpec.describe DatabaseMigrations::BackfillChargeFilterCodesJob do
  subject(:perform) { described_class.perform_now(charge.id) }

  let(:organization) { create(:organization) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:bm_filter) { create(:billable_metric_filter, billable_metric:, key: "region", values: %w[us eu]) }

  let(:plan) { create(:plan, organization:) }
  let(:charge) { create(:standard_charge, plan:, billable_metric:) }

  let(:us_code) { ChargeFilter.generate_code({"region" => ["us"]}) }
  let(:eu_code) { ChargeFilter.generate_code({"region" => ["eu"]}) }

  def build_filter(on, values, **attrs)
    filter = create(:charge_filter, charge: on, **attrs)
    create(:charge_filter_value, charge_filter: filter, billable_metric_filter: bm_filter, values:)
    filter
  end

  it "assigns every filter the code derived from its values" do
    filter = build_filter(charge, ["us"])

    perform

    expect(filter.reload.code).to eq(us_code)
  end

  it "leaves a filter that already has a code untouched" do
    filter = build_filter(charge, ["us"])
    filter.update_column(:code, "assigned_at_creation") # rubocop:disable Rails/SkipsModelValidations

    perform

    expect(filter.reload.code).to eq("assigned_at_creation")
  end

  # Both derive the same code from these values, so they are two filters on one predicate: whichever
  # kept it would be the one that bills, and that is not a migration's call
  it "leaves both filters holding the same values in a different order without a code" do
    first = build_filter(charge, %w[us eu])
    second = build_filter(charge, %w[eu us])

    perform

    expect([first.reload.code, second.reload.code]).to eq([nil, nil])
  end

  it "does nothing when the charge is gone" do
    expect { described_class.perform_now(SecureRandom.uuid) }.not_to raise_error
  end

  # Handed one directly it must still refuse: an override's code comes from the filter it was
  # copied from, and deriving one here would claim a link that was never checked.
  context "when the charge sits on a plan that overrides another" do
    let(:child_plan) { create(:plan, organization:, parent: plan) }

    it "does nothing" do
      child_charge = create(:standard_charge, plan: child_plan, billable_metric:, parent: charge)
      child_filter = build_filter(child_charge, ["us"])

      described_class.perform_now(child_charge.id)

      expect(child_filter.reload.code).to be_nil
    end

    # dependent: :nullify puts parent_id back to NULL when the parent charge is deleted, so an
    # override that lost its parent looks exactly like a plan's own charge by that column.
    it "does nothing even once the charge has lost its parent" do
      orphan = create(:standard_charge, plan: child_plan, billable_metric:, parent: nil)
      orphan_filter = build_filter(orphan, ["us"])

      described_class.perform_now(orphan.id)

      expect(orphan_filter.reload.code).to be_nil
    end
  end

  it "does nothing when the charge was discarded" do
    filter = build_filter(charge, ["us"])
    charge.discard!

    perform

    expect(filter.reload.code).to be_nil
  end

  # Suffixing one of them would decide which is "the" filter from then on, and where the prices
  # differ that is a billing decision.
  context "when two filters on the charge hold the same values" do
    let!(:first) { build_filter(charge, ["us"], properties: {"amount" => "10"}) }
    let!(:second) { build_filter(charge, ["us"], properties: {"amount" => "20"}) }

    it "leaves both of them without codes" do
      perform

      expect([first.reload.code, second.reload.code]).to eq([nil, nil])
    end

    # The pair is the billing decision; a filter on its own predicate is not, and its copies on
    # overrides need its code to link back.
    it "still fills the filters on the charge that are unambiguous" do
      unaffected = build_filter(charge, ["eu"])

      perform

      expect(unaffected.reload.code).to eq(eu_code)
    end
  end

  # Handing the overrides on from here is what makes the ordering unlosable: by the time this
  # runs, the codes it passes down are written.
  describe "handing on to the overrides" do
    it "enqueues the overrides pass for the charge it just filled" do
      build_filter(charge, ["us"])

      expect { perform }.to have_enqueued_job(DatabaseMigrations::BackfillChildChargeFilterCodesJob)
        .with(charge.id)
    end

    it "does not when the charge ended up with nothing to hand down" do
      build_filter(charge, ["us"], properties: {"amount" => "10"})
      build_filter(charge, ["us"], properties: {"amount" => "20"})

      expect { perform }.not_to have_enqueued_job(DatabaseMigrations::BackfillChildChargeFilterCodesJob)
    end

    # A re-run over a charge already filled still has to hand on, since a previous overrides pass
    # may have been the part that failed
    it "still hands on when the codes were already there" do
      build_filter(charge, ["us"]).update_column(:code, us_code) # rubocop:disable Rails/SkipsModelValidations

      expect { perform }.to have_enqueued_job(DatabaseMigrations::BackfillChildChargeFilterCodesJob)
        .with(charge.id)
    end
  end

  # A code already on the charge is the one that filter was created with, so a filter whose
  # values have since collapsed onto it cannot take it.
  it "leaves the charge alone when a derived code is already taken by a sibling" do
    build_filter(charge, ["eu"]).update_column(:code, us_code) # rubocop:disable Rails/SkipsModelValidations
    collapsing = build_filter(charge, ["us"])

    perform

    expect(collapsing.reload.code).to be_nil
  end

  # The upgrade task cannot tell a filter still waiting for a code from one this pass refuses to
  # decide, so it hands the charge out again on every run. That has to be free of consequence.
  it "writes nothing a second time" do
    filter = build_filter(charge, ["us"])
    perform

    expect { described_class.perform_now(charge.id) }.not_to change { filter.reload.code }
  end
end
