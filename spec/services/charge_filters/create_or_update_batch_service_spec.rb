# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChargeFilters::CreateOrUpdateBatchService do
  subject(:service) { described_class.call(charge:, filters_params:, cascade_options:) }

  let(:charge) { create(:standard_charge) }
  let(:filters_params) { {} }
  let(:cascade_options) { {} }

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

      context "with cascade_updates set to true and existing filters" do
        let(:charge_parent) { create(:standard_charge) }
        let(:filter_extra) { create(:charge_filter, charge:) }
        let(:filter_parent) { create(:charge_filter, charge: charge_parent) }
        let(:filter_value_extra) do
          create(
            :charge_filter_value,
            charge_filter: filter_extra,
            billable_metric_filter: card_location_filter,
            values: [card_location_filter.values.second]
          )
        end
        let(:filter_value_parent) do
          create(
            :charge_filter_value,
            charge_filter: filter_parent,
            billable_metric_filter: card_location_filter,
            values: [card_location_filter.values.first]
          )
        end
        let(:cascade_options) do
          {
            cascade: true,
            parent_filters: charge_parent.filters.map(&:attributes)
          }
        end

        before do
          filter_value_extra
          filter_value_parent
        end

        it "discards all filters and the related values that are inherited from parent" do
          expect { service }.to change { filter.reload.discarded? }.to(true)
            .and change { filter_value.reload.discarded? }.to(true)
        end

        it "does not discard filters and the related values that are defined on child" do
          service

          expect(filter_extra.reload.discarded?).to eq(false)
          expect(filter_value_extra.reload.discarded?).to eq(false)
        end
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
          properties: {amount: "20"}.merge(pricing_group_keys)
        }
      ]
    end

    let(:pricing_group_keys) { {pricing_group_keys: ["region"]} }

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

    context "with cascading option" do
      let(:charge_parent) { create(:standard_charge) }
      let(:filter_extra) { create(:charge_filter, charge:) }
      let(:filter_parent) { create(:charge_filter, properties: filter.properties, charge: charge_parent) }
      let(:filter_value_extra) do
        create(
          :charge_filter_value,
          charge_filter: filter_extra,
          billable_metric_filter: card_location_filter,
          values: [card_location_filter.values.second]
        )
      end
      let(:filter_values_parent) do
        [
          create(
            :charge_filter_value,
            charge_filter: filter_parent,
            billable_metric_filter: card_location_filter,
            values: ["domestic"]
          ),
          create(
            :charge_filter_value,
            charge_filter: filter_parent,
            billable_metric_filter: scheme_filter,
            values: ["visa"]
          )
        ]
      end
      let(:cascade_options) do
        {
          cascade: true,
          parent_filters: charge_parent.filters.map(&:attributes)
        }
      end

      before do
        filter_values_parent
        filter_value_extra
      end

      it "updates the filter if child and parent properties are the same" do
        expect { service }.not_to change(ChargeFilter, :count)

        expect(filter.reload).to have_attributes(
          invoice_display_name: "New display name",
          properties: {"amount" => "20", "pricing_group_keys" => ["region"]}
        )
        expect(filter.values.count).to eq(2)
        expect(filter.values.pluck(:values).flatten).to match_array(%w[domestic visa])
      end

      context "when properties are already overridden" do
        let(:properties) { {amount: "755"} }
        let(:pricing_group_keys) { {} }
        let(:filter_parent) { create(:charge_filter, properties:, charge: charge_parent) }

        it "does not update the filter" do
          expect { service }.not_to change(ChargeFilter, :count)

          expect(filter.reload).to have_attributes(
            invoice_display_name: nil,
            properties: charge.properties
          )
          expect(filter.values.count).to eq(2)
          expect(filter.values.pluck(:values).flatten).to match_array(%w[domestic visa])
        end

        context "when properties contains a pricing_group_keys attribute" do
          let(:pricing_group_keys) { {pricing_group_keys: ["region"]} }

          it "updates the filter" do
            expect { service }.not_to change(ChargeFilter, :count)

            expect(filter.reload.pricing_group_keys).to eq(["region"])
            expect(filter.values.count).to eq(2)
            expect(filter.values.pluck(:values).flatten).to match_array(%w[domestic visa])
          end

          context "when filters already have a pricing_group_keys value" do
            let(:filter) { create(:charge_filter, charge:, properties: {amount: "755", pricing_group_keys: ["cloud"]}) }

            it "updates the filter" do
              expect { service }.not_to change(ChargeFilter, :count)

              expect(filter.reload.pricing_group_keys).to eq(["region"])
              expect(filter.values.count).to eq(2)
              expect(filter.values.pluck(:values).flatten).to match_array(%w[domestic visa])
            end
          end
        end

        context "when filters already has a pricing_group_keys value" do
          let(:filter) { create(:charge_filter, charge:, properties: {amount: "755", pricing_group_keys: ["cloud"]}) }
          let(:pricing_group_keys) { {} }

          it "updates the filter" do
            expect { service }.not_to change(ChargeFilter, :count)

            expect(filter.reload.pricing_group_keys).to be_nil
            expect(filter.values.count).to eq(2)
            expect(filter.values.pluck(:values).flatten).to match_array(%w[domestic visa])
          end
        end
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

        it "creates a new filter and removes only the one that matches with parent" do
          result = service

          expect(result.filters.count).to eq(1)
          expect(filter.reload).to be_discarded
          expect(filter_value_extra.reload).not_to be_discarded

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

        it "creates a new filter and removes only the one that matches with parent" do
          result = service

          expect(result.filters.count).to eq(1)
          expect(filter.reload).to be_discarded
          expect(filter_value_extra.reload).not_to be_discarded

          new_filter = result.filters.first
          expect(new_filter.values.count).to eq(2)
          expect(new_filter.values.pluck(:values).flatten).to match_array(%w[domestic visa mastercard])
        end
      end
    end
  end
end
