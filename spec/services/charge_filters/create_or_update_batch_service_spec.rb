# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChargeFilters::CreateOrUpdateBatchService do
  subject(:service) { described_class.call(charge:, filters_params:) }

  let(:charge) { create(:standard_charge) }
  let(:filters_params) { {} }

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

  let(:card_type_filter) do
    create(
      :billable_metric_filter,
      billable_metric: charge.billable_metric,
      key: "card_type",
      values: %w[debit credit]
    )
  end

  context "when filter values hash is empty" do
    let(:filters_params) do
      [
        {
          values: {},
          invoice_display_name: "Invalid filter",
          properties: {amount: "10"}
        }
      ]
    end

    before { card_location_filter }

    it "returns a validation failure" do
      expect(service).not_to be_success
      expect(service.error).to be_a(BaseService::ValidationFailure)
      expect(service.error.messages[:values]).to eq(["value_is_mandatory"])
    end

    it "does not create any filters" do
      expect { service }.not_to change(ChargeFilter, :count)
    end
  end

  context "when filter params is empty" do
    it "does not create any filters" do
      expect { service }.not_to change(ChargeFilter, :count)
    end

    context "when there are existing filters" do
      let(:filter) { create(:charge_filter, charge:) }

      let(:filter_value) do
        create(
          :charge_filter_value,
          charge_filter: filter,
          billable_metric_filter: card_location_filter,
          values: [card_location_filter.values.first]
        )
      end

      before { filter_value }

      it "discards all filters and the related values" do
        expect { service }.to change { filter.reload.discarded? }.to(true)
          .and change { filter_value.reload.discarded? }.to(true)
      end
    end
  end

  context "with new filters" do
    let(:filters_params) do
      [
        {
          values: {
            card_location_filter.key => ["domestic"],
            scheme_filter.key => ["visa"]
          },
          invoice_display_name: "Visa domestic card payment",
          properties: {amount: "10"}
        },
        {
          values: {
            card_location_filter.key => ["domestic"],
            scheme_filter.key => ["visa"],
            card_type_filter.key => ["debit"]
          },
          invoice_display_name: "Visa debit domestic card payment",
          properties: {amount: "20", pricing_group_keys: ["region"]}
        }
      ]
    end

    it "creates the filters and their values" do
      expect { service }.to change(ChargeFilter, :count).by(2)

      filter1 = charge.filters.find_by(invoice_display_name: "Visa domestic card payment")
      expect(filter1).to have_attributes(
        invoice_display_name: "Visa domestic card payment",
        properties: {"amount" => "10"}
      )
      expect(filter1.values.count).to eq(2)
      expect(filter1.values.pluck(:values).flatten).to match_array(%w[domestic visa])

      filter2 = charge.filters.find_by(invoice_display_name: "Visa debit domestic card payment")
      expect(filter2).to have_attributes(
        invoice_display_name: "Visa debit domestic card payment",
        properties: {"amount" => "20", "pricing_group_keys" => ["region"]}
      )
      expect(filter2.values.count).to eq(3)
      expect(filter2.values.pluck(:values).flatten).to match_array(%w[domestic visa debit])
    end

    context "when filters properties contain not relevant values" do
      let(:charge) { create(:graduated_charge) }
      let(:filters_params) do
        [
          {
            values: {
              card_location_filter.key => ["domestic"],
              scheme_filter.key => ["visa"]
            },
            invoice_display_name: "Visa domestic card payment",
            properties: {amount: "10", graduated_ranges: [{from_value: 0, to_value: nil, per_unit_amount: "0", flat_amount: "200"}]}
          },
          {
            values: {
              card_location_filter.key => ["domestic"],
              scheme_filter.key => ["visa"],
              card_type_filter.key => ["debit"]
            },
            invoice_display_name: "Visa debit domestic card payment",
            properties: {amount: "20", graduated_ranges: [{from_value: 0, to_value: nil, per_unit_amount: "0", flat_amount: "200"}]}
          }
        ]
      end

      it "removes the not relevant values from the properties" do
        expect { service }.to change(ChargeFilter, :count).by(2)

        filter1 = charge.filters.find_by(invoice_display_name: "Visa domestic card payment")
        expect(filter1.properties).to eq("graduated_ranges" => [
          {"from_value" => 0, "to_value" => nil, "per_unit_amount" => "0", "flat_amount" => "200"}
        ])

        filter2 = charge.filters.find_by(invoice_display_name: "Visa debit domestic card payment")
        expect(filter2.properties).to eq("graduated_ranges" => [
          {"from_value" => 0, "to_value" => nil, "per_unit_amount" => "0", "flat_amount" => "200"}
        ])
      end
    end
  end

  context "with existing filters" do
    let(:filter) { create(:charge_filter, charge:) }
    let(:filter_values) do
      [
        create(
          :charge_filter_value,
          charge_filter: filter,
          billable_metric_filter: card_location_filter,
          values: ["domestic"]
        ),
        create(
          :charge_filter_value,
          charge_filter: filter,
          billable_metric_filter: scheme_filter,
          values: ["visa"]
        )
      ]
    end

    let(:filters_params) do
      [
        {
          values: {
            card_location_filter.key => ["domestic"],
            scheme_filter.key => ["visa"]
          },
          invoice_display_name: "New display name",
          properties: {amount: "20"}.merge(pricing_group_keys).merge(presentation_group_keys)
        }
      ]
    end

    let(:pricing_group_keys) { {pricing_group_keys: ["region"]} }
    let(:presentation_group_keys) { {} }

    before { filter_values }

    it "updates the filter" do
      expect { service }.not_to change(ChargeFilter, :count)
      expect(filter.reload).to have_attributes(
        invoice_display_name: "New display name",
        properties: {"amount" => "20", "pricing_group_keys" => ["region"]}
      )
      expect(filter.values.count).to eq(2)
      expect(filter.values.pluck(:values).flatten).to match_array(%w[domestic visa])
    end

    context "when changing filter values" do
      let(:filters_params) do
        [
          {
            values: {
              card_location_filter.key => ["international"],
              scheme_filter.key => ["mastercard"]
            },
            invoice_display_name: "New display name",
            properties: {amount: "20"}
          }
        ]
      end

      it "creates a new filter and removes the existing one" do
        result = service

        expect(result.filters.count).to eq(1)
        expect(filter.reload).to be_discarded

        new_filter = result.filters.first
        expect(new_filter.values.count).to eq(2)
        expect(new_filter.values.pluck(:values).flatten).to match_array(%w[international mastercard])
      end
    end

    context "when adding a value into filter values" do
      let(:filters_params) do
        [
          {
            values: {
              card_location_filter.key => ["domestic"],
              scheme_filter.key => %w[visa mastercard]
            },
            invoice_display_name: "New display name",
            properties: {amount: "20"}
          }
        ]
      end

      it "creates a new filter and removes the existing one" do
        result = service

        expect(result.filters.count).to eq(1)
        expect(filter.reload).to be_discarded

        new_filter = result.filters.first
        expect(new_filter.values.count).to eq(2)
        expect(new_filter.values.pluck(:values).flatten).to match_array(%w[domestic visa mastercard])
      end
    end
  end
end
