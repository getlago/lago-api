# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::ContractAlert do
  subject(:alert) { build(:contract_alert, organization:, contract_external_id: contract.external_id) }

  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:customer) { create_default(:customer) }
  let_it_be(:contract) { create(:contract) }

  describe "enums" do
    it do
      expect(alert).to define_enum_for(:direction)
        .backed_by_column_of_type(:enum)
        .validating
        .with_values(increasing: "increasing", decreasing: "decreasing")
    end
  end

  describe "associations" do
    it do
      expect(alert).to belong_to(:organization)
      expect(alert).to belong_to(:product).optional
      expect(alert).to belong_to(:product_filter).optional
      expect(alert).to have_many(:thresholds).class_name("UsageMonitoring::ContractAlertThreshold")
        .dependent(:delete_all).inverse_of(:alert)
      expect(alert).to have_many(:triggered_alerts).class_name("UsageMonitoring::ContractTriggeredAlert")
        .conditions(kind: "triggered")
      expect(alert).to have_many(:all_triggered_alerts).class_name("UsageMonitoring::ContractTriggeredAlert")
        .inverse_of(:alert)
    end

    it "resolves a discarded product and product filter" do
      product_filter = create(:product_filter)
      product = product_filter.product
      alert = create(:contract_usage_units_alert, contract_external_id: contract.external_id, product:, product_filter:)

      product_filter.discard!
      product.discard!

      expect(described_class.find(alert.id)).to have_attributes(product:, product_filter:)
    end
  end

  describe "validations" do
    it do
      expect(alert).to validate_presence_of(:code)
      expect(alert).to validate_presence_of(:contract_external_id)
      expect(alert).to validate_inclusion_of(:alert_type).in_array(%w[usage_amount usage_units])
    end

    describe "scope validation" do
      let(:product) { create(:product) }
      let(:product_filter) { create(:product_filter, product:) }

      it "accepts a product filter of its product" do
        alert.assign_attributes(product:, product_filter:)

        expect(alert).to be_valid
      end

      it "refuses a product filter without its product" do
        alert.product_filter = product_filter

        expect(alert).to be_invalid
        expect(alert.errors[:product]).to eq(["value_is_mandatory"])
      end

      it "refuses a product filter of another product" do
        alert.assign_attributes(product: create(:product), product_filter:)

        expect(alert).to be_invalid
        expect(alert.errors[:product_filter]).to eq(["value_is_invalid"])
      end

      it "accepts with_product_filters on a product" do
        alert.assign_attributes(product:, with_product_filters: true)

        expect(alert).to be_valid
      end

      it "refuses with_product_filters without a product" do
        alert.with_product_filters = true

        expect(alert).to be_invalid
        expect(alert.errors[:with_product_filters]).to eq(["value_is_invalid"])
      end

      it "refuses with_product_filters on a product filter" do
        alert.assign_attributes(product:, product_filter:, with_product_filters: true)

        expect(alert).to be_invalid
        expect(alert.errors[:with_product_filters]).to eq(["value_is_invalid"])
      end
    end
  end

  describe ".find_sti_class" do
    it "returns the class of each alert type" do
      expect(described_class.find_sti_class("usage_amount")).to eq(UsageMonitoring::ContractUsageAmountAlert)
      expect(described_class.find_sti_class("usage_units")).to eq(UsageMonitoring::ContractUsageUnitsAlert)
    end

    it "raises KeyError for an unknown alert type" do
      expect { described_class.find_sti_class("current_usage_amount") }.to raise_error(KeyError)
    end
  end

  describe ".sti_name" do
    it "returns the alert type of each subclass" do
      expect(UsageMonitoring::ContractUsageAmountAlert.sti_name).to eq("usage_amount")
      expect(UsageMonitoring::ContractUsageUnitsAlert.sti_name).to eq("usage_units")
    end
  end

  describe "#find_thresholds_crossed" do
    let(:alert) do
      create(
        :contract_alert,
        contract_external_id: contract.external_id,
        thresholds: [10, 30, 50],
        recurring_threshold: 100,
        previous_value: 33
      )
    end

    it "returns the one-time and recurring thresholds between previous_value and current" do
      # 50 is the last one-time threshold, then one recurring step of 100 at 150, 250 and 350
      expect(alert.find_thresholds_crossed(351)).to eq([50, 150, 250, 350])
    end

    it "records the crossing in the contract triggered alerts" do
      crossed = alert.find_thresholds_crossed(351)
      triggered_alert = alert.all_triggered_alerts.create!(
        organization:,
        alertable: contract,
        current_value: 351,
        previous_value: alert.previous_value,
        crossed_thresholds: alert.formatted_crossed_thresholds(crossed),
        triggered_at: Time.current
      )

      expect(alert.triggered_alerts).to eq([triggered_alert])
      expect(triggered_alert.reload).to have_attributes(contract:, alert:)
      expect(triggered_alert.crossed_thresholds).to eq([
        {"code" => "warn50", "value" => "50.0", "recurring" => false},
        {"code" => "rec", "value" => "150.0", "recurring" => true},
        {"code" => "rec", "value" => "250.0", "recurring" => true},
        {"code" => "rec", "value" => "350.0", "recurring" => true}
      ])
      expect(alert.recorded_alarm_codes).to eq(Set["warn50", "rec"])
    end
  end
end
