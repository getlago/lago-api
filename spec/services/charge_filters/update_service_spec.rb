# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChargeFilters::UpdateService do
  subject(:service) { described_class.call(charge_filter:, params:) }

  let(:charge) { create(:standard_charge) }
  let(:charge_filter) { create(:charge_filter, charge:, invoice_display_name: "Original Name", properties: {"amount" => "10"}) }
  let(:params) { {} }

  let(:card_location_filter) do
    create(
      :billable_metric_filter,
      billable_metric: charge.billable_metric,
      key: "card_location",
      values: %w[domestic international]
    )
  end

  describe "#call" do
    context "when charge_filter is nil" do
      subject(:service) { described_class.call(charge_filter: nil, params: {}) }

      it "returns not found failure" do
        expect(service).not_to be_success
        expect(service.error).to be_a(BaseService::NotFoundFailure)
        expect(service.error.resource).to eq("charge_filter")
      end
    end

    context "when updating invoice_display_name and properties" do
      let(:params) do
        {
          invoice_display_name: "New Display Name",
          properties: {amount: "200"}
        }
      end

      before do
        create(:charge_filter_value, charge_filter:, billable_metric_filter: card_location_filter, values: ["domestic"])
      end

      it "updates both attributes" do
        expect(service).to be_success
        expect(charge_filter.reload).to have_attributes(
          invoice_display_name: "New Display Name",
          properties: {"amount" => "200"}
        )
      end
    end

    context "with graduated charge model" do
      let(:charge) { create(:graduated_charge) }
      let(:charge_filter) { create(:charge_filter, charge:, properties: {"graduated_ranges" => [{"from_value" => 0, "to_value" => nil, "per_unit_amount" => "0", "flat_amount" => "100"}]}) }
      let(:params) do
        {
          properties: {
            amount: "10",
            graduated_ranges: [{from_value: 0, to_value: nil, per_unit_amount: "0", flat_amount: "200"}]
          }
        }
      end

      it "filters properties based on charge model" do
        expect(service).to be_success
        expect(charge_filter.reload.properties).to eq(
          "graduated_ranges" => [
            {"from_value" => 0, "to_value" => nil, "per_unit_amount" => "0", "flat_amount" => "200"}
          ]
        )
      end
    end
  end
end
