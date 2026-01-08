# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChargeFilters::DestroyService do
  subject(:service) { described_class.call(charge_filter:) }

  let(:charge) { create(:standard_charge) }
  let(:charge_filter) { create(:charge_filter, charge:) }

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
      subject(:service) { described_class.call(charge_filter: nil) }

      it "returns not found failure" do
        expect(service).not_to be_success
        expect(service.error).to be_a(BaseService::NotFoundFailure)
        expect(service.error.resource).to eq("charge_filter")
      end
    end

    context "with valid charge_filter" do
      let(:filter_value) do
        create(:charge_filter_value, charge_filter:, billable_metric_filter: card_location_filter, values: ["domestic"])
      end

      before { filter_value }

      it "soft deletes the charge filter" do
        expect { service }.to change { charge_filter.reload.discarded? }.from(false).to(true)
        expect(service).to be_success
        expect(service.charge_filter).to eq(charge_filter)
      end

      it "soft deletes the charge filter values" do
        expect { service }.to change { filter_value.reload.discarded? }.from(false).to(true)
      end

      it "returns the discarded charge filter" do
        result = service
        expect(result.charge_filter.deleted_at).to be_present
      end
    end
  end
end
