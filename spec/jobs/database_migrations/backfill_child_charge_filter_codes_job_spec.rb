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

  # The parent's code was frozen at creation and its values moved afterwards, so it no longer
  # matches what those values produce today. The override is still a copy of it.
  it "copies a parent code its own values no longer derive" do
    build_filter(parent_charge, ["us"], code: "frozen_before_the_values_moved")
    child_filter = build_filter(child_charge, ["us"])

    perform

    expect(child_filter.reload.code).to eq("frozen_before_the_values_moved")
  end

  # The override is a copy of that filter, and both sides derive the same code from these values.
  # Reading the two as different would leave a link that exists unrecorded.
  it "copies the parent code when the two hold the values in a different order" do
    build_filter(parent_charge, %w[us eu], code: "frozen_us_eu")
    child_filter = build_filter(child_charge, %w[eu us])

    perform

    expect(child_filter.reload.code).to eq("frozen_us_eu")
  end

  # It cannot say which of the two the override was copied from
  it "copies nothing for a predicate the parent holds twice" do
    build_filter(parent_charge, ["us"], code: us_code, properties: {"amount" => "1"})
    build_filter(parent_charge, ["us"], code: "#{us_code}_2", properties: {"amount" => "2"})
    child_filter = build_filter(child_charge, ["us"])

    perform

    expect(child_filter.reload.code).to be_nil
  end

  it "gives every override of the parent the codes it holds" do
    build_filter(parent_charge, ["us"], code: us_code)
    build_filter(parent_charge, ["eu"], code: eu_code)

    filters = Array.new(3) do
      other_plan = create(:plan, organization:, parent: plan)
      other_child = create(:standard_charge, plan: other_plan, billable_metric:, parent: parent_charge)
      [build_filter(other_child, ["us"]), build_filter(other_child, ["eu"])]
    end.flatten

    perform

    expect(filters.map { it.reload.code }).to eq([us_code, eu_code] * 3)
  end

  # The walk reads an override, then writes minutes later. A propagation or an API edit in between
  # assigns a code of its own, and that one was assigned at creation.
  it "leaves a code that appeared between reading the override and writing to it" do
    build_filter(parent_charge, ["us"], code: us_code)
    child_filter = build_filter(child_charge, ["us"])

    # Hooked on the write itself, which is the only place the window can be reproduced: the batch has
    # been read and matched by now, and the code appears before the statement runs
    allow_any_instance_of(described_class).to receive(:write_codes).and_wrap_original do |original, *args| # rubocop:disable RSpec/AnyInstance
      child_filter.update_column(:code, "assigned_while_the_walk_was_running") # rubocop:disable Rails/SkipsModelValidations
      original.call(*args)
    end

    perform

    expect(child_filter.reload.code).to eq("assigned_while_the_walk_was_running")
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

  # The sibling froze this code when its own values were these. Writing it again would break the
  # unique index on (charge_id, code), and take every other filter in the same statement with it.
  it "leaves the filter without a code when a sibling on the override already holds it" do
    build_filter(parent_charge, ["us"], code: us_code)
    build_filter(child_charge, ["eu"], code: us_code)
    filter = build_filter(child_charge, ["us"])

    perform

    expect(filter.reload.code).to be_nil
  end

  # A filter is known by its values, so what counts as the same values is what the pairing rests on
  describe "what counts as the same filter" do
    let(:bm_filter) do
      create(:billable_metric_filter, billable_metric:, key: "region",
        values: %w[us eu US usa a+b a b ação acao x1 x2 x10])
    end

    it "pairs mixed case held in a different order" do
      build_filter(parent_charge, %w[US us], code: "frozen_on_the_plan")
      filter = build_filter(child_charge, %w[us US])

      perform

      expect(filter.reload.code).to eq("frozen_on_the_plan")
    end

    it "pairs values that look numeric, which sort as text" do
      build_filter(parent_charge, %w[x1 x2 x10], code: "frozen_on_the_plan")
      filter = build_filter(child_charge, %w[x10 x2 x1])

      perform

      expect(filter.reload.code).to eq("frozen_on_the_plan")
    end

    it "pairs a value holding the separator the code derives with" do
      build_filter(parent_charge, ["a+b"], code: "frozen_on_the_plan")
      filter = build_filter(child_charge, ["a+b"])

      perform

      expect(filter.reload.code).to eq("frozen_on_the_plan")
    end

    it "does not pair values differing only in case" do
      build_filter(parent_charge, %w[us], code: "frozen_on_the_plan")
      filter = build_filter(child_charge, %w[US])

      perform

      expect(filter.reload.code).to be_nil
    end

    # Otherwise a filter could take the code of the one whose values the separator makes it look like
    it "does not pair a joined value with the two values it looks like" do
      build_filter(parent_charge, ["a+b"], code: "frozen_on_the_plan")
      filter = build_filter(child_charge, %w[a b])

      perform

      expect(filter.reload.code).to be_nil
    end

    it "does not pair an accented value with its plain form" do
      build_filter(parent_charge, %w[ação], code: "frozen_on_the_plan")
      filter = build_filter(child_charge, %w[acao])

      perform

      expect(filter.reload.code).to be_nil
    end

    it "does not pair a value with one that is a prefix of it" do
      build_filter(parent_charge, %w[us], code: "frozen_on_the_plan")
      filter = build_filter(child_charge, %w[us usa])

      perform

      expect(filter.reload.code).to be_nil
    end
  end

  describe "filters naming more than one key, or none" do
    let(:tier_filter) { create(:billable_metric_filter, billable_metric:, key: "tier", values: %w[gold silver]) }

    # Several keys, or none at all, which `build_filter` cannot express
    def build_filter_with(charge, values_by_metric_filter, code: nil)
      filter = create(:charge_filter, charge:)
      values_by_metric_filter.each do |metric_filter, values|
        create(:charge_filter_value, charge_filter: filter, billable_metric_filter: metric_filter, values:)
      end
      filter.update_column(:code, code) if code # rubocop:disable Rails/SkipsModelValidations
      filter
    end

    it "pairs when both name the same two keys" do
      build_filter_with(parent_charge, {bm_filter => %w[us], tier_filter => %w[gold]}, code: "two_keys")
      filter = build_filter_with(child_charge, {bm_filter => %w[us], tier_filter => %w[gold]})

      perform

      expect(filter.reload.code).to eq("two_keys")
    end

    it "does not pair when the override names a key the plan does not" do
      build_filter_with(parent_charge, {bm_filter => %w[us]}, code: "one_key")
      filter = build_filter_with(child_charge, {bm_filter => %w[us], tier_filter => %w[gold]})

      perform

      expect(filter.reload.code).to be_nil
    end

    it "does not pair when the override is missing a key the plan names" do
      build_filter_with(parent_charge, {bm_filter => %w[us], tier_filter => %w[gold]}, code: "two_keys")
      filter = build_filter_with(child_charge, {bm_filter => %w[us]})

      perform

      expect(filter.reload.code).to be_nil
    end

    it "pairs two filters that hold no values at all" do
      build_filter_with(parent_charge, {}, code: "no_values")
      filter = build_filter_with(child_charge, {})

      perform

      expect(filter.reload.code).to eq("no_values")
    end

    it "does not pair one holding no values with one that holds some" do
      build_filter_with(parent_charge, {}, code: "no_values")
      filter = build_filter_with(child_charge, {bm_filter => %w[us]})

      perform

      expect(filter.reload.code).to be_nil
    end
  end

  # The pairing reads live values on both sides, and the two sides have to agree on that
  describe "discarded rows" do
    it "does not pair an override filter whose values are discarded" do
      build_filter(parent_charge, ["us"], code: us_code)
      filter = build_filter(child_charge, ["us"])
      filter.values.each(&:discard!)

      perform

      expect(filter.reload.code).to be_nil
    end

    it "does not hand down a code from a plan filter whose values are discarded" do
      build_filter(parent_charge, ["us"], code: us_code).values.each(&:discard!)
      filter = build_filter(child_charge, ["us"])

      perform

      expect(filter.reload.code).to be_nil
    end

    it "does not read a discarded duplicate as ambiguous" do
      build_filter(parent_charge, ["us"], code: us_code)
      build_filter(child_charge, ["us"]).discard!
      filter = build_filter(child_charge, ["us"])

      perform

      expect(filter.reload.code).to eq(us_code)
    end
  end
end
