# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Customers::Usage::ProjectedCharge do
  subject { described_class }

  it do
    expect(subject).to have_field(:id).of_type("ID!")
    expect(subject).to have_field(:amount_cents).of_type("BigInt!")
    expect(subject).to have_field(:projected_amount_cents).of_type("BigInt!")
    expect(subject).to have_field(:events_count).of_type("Int!")
    expect(subject).to have_field(:units).of_type("Float!")
    expect(subject).to have_field(:projected_units).of_type("Float!")
    expect(subject).to have_field(:billable_metric).of_type("BillableMetric!")
    expect(subject).to have_field(:charge).of_type("Charge!")
    expect(subject).to have_field(:grouped_usage).of_type("[ProjectedGroupedChargeUsage!]!")
    expect(subject).to have_field(:filters).of_type("[ProjectedChargeFilterUsage!]")
    expect(subject).to have_field(:pricing_unit_amount_cents).of_type("BigInt")
    expect(subject).to have_field(:pricing_unit_projected_amount_cents).of_type("BigInt")
  end

  describe "#presentation_breakdowns" do
    subject(:presentation_breakdowns) { run_graphql_field("ProjectedChargeUsage.presentationBreakdowns", fees) }

    let(:fees) { [ungrouped_fee, grouped_fee] }

    let(:ungrouped_fee) do
      build(
        :charge_fee,
        grouped_by: {},
        presentation_breakdowns: [build(:presentation_breakdown, presentation_by: {"cloud" => "aws"}, units: 1.0)]
      )
    end

    let(:grouped_fee) do
      build(
        :charge_fee,
        grouped_by: {"agent_name" => "frodo"},
        presentation_breakdowns: [build(:presentation_breakdown, presentation_by: {"cloud" => "aws"}, units: 3.0)]
      )
    end

    it "returns breakdowns only for ungrouped fees" do
      expect(presentation_breakdowns).to eq([
        {presentation_by: {"cloud" => "aws"}, units: "1.0"}
      ])
    end
  end
end
