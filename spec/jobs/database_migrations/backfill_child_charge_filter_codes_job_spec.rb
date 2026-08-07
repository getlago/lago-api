# frozen_string_literal: true

require "rails_helper"

RSpec.describe DatabaseMigrations::BackfillChildChargeFilterCodesJob do
  subject(:perform) { described_class.perform_now(parent_charge.id) }

  let(:organization) { create(:organization) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:bm_filter) { create(:billable_metric_filter, billable_metric:, key: "region", values: %w[us eu]) }

  let(:plan) { create(:plan, organization:) }
  let(:parent_charge) { create(:standard_charge, plan:, billable_metric:) }

  let(:child_plan) { create(:plan, organization:, parent: plan) }
  let(:child_charge) { create(:standard_charge, plan: child_plan, billable_metric:, parent: parent_charge) }

  let(:us_code) { ChargeFilter.generate_code({"region" => ["us"]}) }
  let(:eu_code) { ChargeFilter.generate_code({"region" => ["eu"]}) }

  def build_filter(on, values, code: nil, **attrs)
    filter = create(:charge_filter, charge: on, **attrs)
    create(:charge_filter_value, charge_filter: filter, billable_metric_filter: bm_filter, values:)
    filter.update_column(:code, code) if code # rubocop:disable Rails/SkipsModelValidations
    filter
  end

  it "gives the override's filter the code its parent holds" do
    build_filter(parent_charge, ["us"], code: us_code)
    child_filter = build_filter(child_charge, ["us"], properties: {"amount" => "1"})

    perform

    expect(child_filter.reload.code).to eq(us_code)
  end

  # The override kept a filter its plan no longer has, so there is no link left to record
  it "leaves a filter the parent does not hold without a code" do
    build_filter(parent_charge, ["us"], code: us_code)
    orphan = build_filter(child_charge, ["eu"])

    perform

    expect(orphan.reload.code).to be_nil
  end

  it "does nothing when the parent has no codes yet" do
    build_filter(parent_charge, ["us"])
    child_filter = build_filter(child_charge, ["us"])

    perform

    expect(child_filter.reload.code).to be_nil
  end

  it "leaves a filter that already has a code untouched" do
    build_filter(parent_charge, ["us"], code: us_code)
    child_filter = build_filter(child_charge, ["us"], code: "inherited_on_propagation")

    perform

    expect(child_filter.reload.code).to eq("inherited_on_propagation")
  end

  # Same rule as the parents pass: choosing which of them keeps the code decides which one bills
  it "leaves both of two filters sharing a code without one" do
    build_filter(parent_charge, ["us"], code: us_code)
    first = build_filter(child_charge, ["us"], properties: {"amount" => "1"})
    second = build_filter(child_charge, ["us"], properties: {"amount" => "2"})

    perform

    expect([first.reload.code, second.reload.code]).to eq([nil, nil])
  end

  it "still fills the filters on the override that are unambiguous" do
    build_filter(parent_charge, ["us"], code: us_code)
    build_filter(parent_charge, ["eu"], code: eu_code)
    build_filter(child_charge, ["us"], properties: {"amount" => "1"})
    build_filter(child_charge, ["us"], properties: {"amount" => "2"})
    unaffected = build_filter(child_charge, ["eu"])

    perform

    expect(unaffected.reload.code).to eq(eu_code)
  end

  it "reaches every override of the parent" do
    build_filter(parent_charge, ["us"], code: us_code)
    other_child_plan = create(:plan, organization:, parent: plan)
    other_child = create(:standard_charge, plan: other_child_plan, billable_metric:, parent: parent_charge)
    filters = [build_filter(child_charge, ["us"]), build_filter(other_child, ["us"])]

    perform

    expect(filters.map { it.reload.code }).to eq([us_code, us_code])
  end

  # The loop carries its own cursor, so it has to walk past the end of a batch
  it "keeps going past the first batch of overrides" do
    stub_const("#{described_class}::MAX_FILTERS_PER_BATCH", 1)
    build_filter(parent_charge, ["us"], code: us_code)

    filters = Array.new(3) do
      other_plan = create(:plan, organization:, parent: plan)
      other_child = create(:standard_charge, plan: other_plan, billable_metric:, parent: parent_charge)
      build_filter(other_child, ["us"])
    end

    perform

    expect(filters.map { it.reload.code }).to eq([us_code] * 3)
  end

  # The parent's code was frozen at creation and its values moved afterwards, so it no longer
  # matches what those values produce today. The override is still a copy of it.
  it "copies a parent code its own values no longer derive" do
    build_filter(parent_charge, ["us"], code: "frozen_before_the_values_moved")
    child_filter = build_filter(child_charge, ["us"])

    perform

    expect(child_filter.reload.code).to eq("frozen_before_the_values_moved")
  end

  # It cannot say which of the two the override was copied from
  it "copies nothing for a predicate the parent holds twice" do
    build_filter(parent_charge, ["us"], code: us_code, properties: {"amount" => "1"})
    build_filter(parent_charge, ["us"], code: "#{us_code}_2", properties: {"amount" => "2"})
    child_filter = build_filter(child_charge, ["us"])

    perform

    expect(child_filter.reload.code).to be_nil
  end

  it "does nothing when the charge is gone" do
    expect { described_class.perform_now(SecureRandom.uuid) }.not_to raise_error
  end

  it "does nothing when handed an override rather than a plan's charge" do
    build_filter(parent_charge, ["us"], code: us_code)
    grandchild_plan = create(:plan, organization:, parent: child_plan)
    grandchild = create(:standard_charge, plan: grandchild_plan, billable_metric:, parent: child_charge)
    filter = build_filter(grandchild, ["us"])

    described_class.perform_now(child_charge.id)

    expect(filter.reload.code).to be_nil
  end
end
