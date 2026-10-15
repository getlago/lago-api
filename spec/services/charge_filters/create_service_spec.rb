# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChargeFilters::CreateService do
  subject(:service) { described_class.call(charge:, params:) }

  let(:charge) { create(:standard_charge) }
  let(:params) { {} }

  let(:card_location_filter) do
    create(
      :billable_metric_filter,
      billable_metric: charge.billable_metric,
      key: "card_location",
      values: %w[domestic international]
    )
  end

  let(:scheme_filter) do
    create(
      :billable_metric_filter,
      billable_metric: charge.billable_metric,
      key: "scheme",
      values: %w[visa mastercard]
    )
  end

  describe "#call" do
    context "when charge is nil" do
      let(:charge) { nil }

      it "returns not found failure" do
        expect(service).not_to be_success
        expect(service.error).to be_a(BaseService::NotFoundFailure)
        expect(service.error.resource).to eq("charge")
      end
    end

    context "when values are empty" do
      let(:params) do
        {
          invoice_display_name: "Test Filter",
          properties: {amount: "10"},
          values: {}
        }
      end

      before { card_location_filter }

      it "returns a validation failure" do
        expect(service).not_to be_success
        expect(service.error).to be_a(BaseService::ValidationFailure)
        expect(service.error.messages[:values]).to eq(["value_is_mandatory"])
      end
    end

    context "when values are missing" do
      let(:params) do
        {
          invoice_display_name: "Test Filter",
          properties: {amount: "10"}
        }
      end

      before { card_location_filter }

      it "returns a validation failure" do
        expect(service).not_to be_success
        expect(service.error).to be_a(BaseService::ValidationFailure)
        expect(service.error.messages[:values]).to eq(["value_is_mandatory"])
      end
    end

    context "with valid params" do
      let(:params) do
        {
          invoice_display_name: "Domestic Visa",
          properties: {amount: "50"},
          values: {
            card_location_filter.key => ["domestic"],
            scheme_filter.key => ["visa"]
          }
        }
      end

      it "creates a charge filter" do
        expect { service }.to change(ChargeFilter, :count).by(1)
        expect(service).to be_success

        charge_filter = service.charge_filter
        expect(charge_filter).to have_attributes(
          invoice_display_name: "Domestic Visa",
          properties: {"amount" => "50"},
          organization_id: charge.organization_id
        )
      end

      it "creates charge filter values" do
        expect { service }.to change(ChargeFilterValue, :count).by(2)

        charge_filter = service.charge_filter
        expect(charge_filter.values.count).to eq(2)
        expect(charge_filter.to_h).to eq({
          "card_location" => ["domestic"],
          "scheme" => ["visa"]
        })
      end
    end

    context "with cascade_updates" do
      subject(:service) { described_class.call(charge:, params:, cascade_updates: true) }

      let(:child_plan) { create(:plan, organization: charge.organization, parent: charge.plan) }
      let(:child_charge) do
        create(:standard_charge, plan: child_plan, organization: charge.organization, billable_metric: charge.billable_metric, parent: charge)
      end

      let(:params) do
        {
          invoice_display_name: "Domestic Visa",
          properties: {amount: "50"},
          values: {card_location_filter.key => ["domestic"]}
        }
      end

      before do
        create(:subscription, plan: child_plan, status: :active)
        child_charge
      end

      # The children are matched on this code, so the filter created here has to hand over
      # the one it was just given rather than let the cascade fall back to the predicate
      it "triggers filter-level cascade carrying the new filter's code" do
        result = service

        expect(result.charge_filter.code).to be_present
        expect(ChargeFilters::CascadeJob).to have_been_enqueued.with(
          charge.id,
          "create",
          hash_including("card_location"),
          nil,
          hash_including("amount"),
          "Domestic Visa",
          result.charge_filter.code
        )
      end
    end

    context "without cascade_updates when charge has children" do
      let(:child_plan) { create(:plan, organization: charge.organization, parent: charge.plan) }
      let(:child_charge) do
        create(:standard_charge, plan: child_plan, organization: charge.organization, billable_metric: charge.billable_metric, parent: charge)
      end

      let(:params) do
        {
          invoice_display_name: "Domestic Visa",
          properties: {amount: "50"},
          values: {card_location_filter.key => ["domestic"]}
        }
      end

      before do
        create(:subscription, plan: child_plan, status: :active)
        child_charge
      end

      it "does not trigger cascade update" do
        service

        expect(ChargeFilters::CascadeJob).not_to have_been_enqueued
      end
    end

    # Nothing to cascade to, so the job would find no children and do nothing
    context "with cascade_updates when charge has no children" do
      subject(:service) { described_class.call(charge:, params:, cascade_updates: true) }

      let(:params) do
        {
          invoice_display_name: "Domestic Visa",
          properties: {amount: "50"},
          values: {card_location_filter.key => ["domestic"]}
        }
      end

      it "creates the filter without enqueuing a cascade job" do
        expect { service }.to change(ChargeFilter, :count).by(1)
        expect(ChargeFilters::CascadeJob).not_to have_been_enqueued
      end
    end

    context "with graduated charge model" do
      let(:charge) { create(:graduated_charge) }
      let(:params) do
        {
          invoice_display_name: "Domestic Filter",
          properties: {
            amount: "10",
            graduated_ranges: [{from_value: 0, to_value: nil, per_unit_amount: "0", flat_amount: "200"}]
          },
          values: {card_location_filter.key => ["domestic"]}
        }
      end

      it "filters properties based on charge model" do
        expect(service).to be_success

        charge_filter = service.charge_filter
        expect(charge_filter.properties).to eq(
          "graduated_ranges" => [
            {"from_value" => 0, "to_value" => nil, "per_unit_amount" => "0", "flat_amount" => "200"}
          ]
        )
        expect(charge_filter.properties).not_to have_key("amount")
      end
    end

    context "with pricing_group_keys in properties" do
      let(:params) do
        {
          invoice_display_name: "Grouped Filter",
          properties: {amount: "30", pricing_group_keys: ["region"]},
          values: {card_location_filter.key => ["domestic"]}
        }
      end

      it "preserves pricing_group_keys in properties" do
        expect(service).to be_success

        charge_filter = service.charge_filter
        expect(charge_filter.properties).to eq({
          "amount" => "30",
          "pricing_group_keys" => ["region"]
        })
      end
    end

    context "with presentation_group_keys in properties" do
      let(:params) do
        {
          invoice_display_name: "Domestic Filter",
          properties: {amount: "50", presentation_group_keys: [{value: "region"}]},
          values: {card_location_filter.key => ["domestic"]}
        }
      end

      it "ignores presentation_group_keys" do
        expect(service).to be_success

        charge_filter = service.charge_filter
        expect(charge_filter.properties).to eq({"amount" => "50"})
        expect(charge_filter.properties).not_to have_key("presentation_group_keys")
      end
    end
  end
end
