# frozen_string_literal: true

require "rails_helper"

RSpec.describe Clickhouse::ProductEventsRaw, clickhouse: true do
  subject(:product_event) do
    build(:clickhouse_product_events_raw, organization:, external_contract_id: "contract_1", timestamp:)
  end

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:timestamp) { Time.zone.parse("2026-11-01 10:00:00") }

  describe "#external_subscription_id" do
    it "returns the contract" do
      expect(product_event.external_subscription_id).to eq("contract_1")
    end
  end

  describe "#contract" do
    let(:active_contract) do
      create(:contract, customer:, external_id: "contract_1", started_at: timestamp - 1.month)
    end

    before { active_contract }

    it "returns the contract started before the event" do
      expect(product_event.contract).to eq(active_contract)
      expect(product_event.customer).to eq(customer)
    end

    context "with a canceled contract started later" do
      before do
        create(:contract, :canceled, customer:, external_id: "contract_1", started_at: timestamp - 1.day)
      end

      it "ignores the canceled contract" do
        expect(product_event.contract).to eq(active_contract)
      end
    end

    context "with a contract started in the same millisecond as the event" do
      let(:active_contract) do
        create(:contract, customer:, external_id: "contract_1", started_at: timestamp + 0.000456)
      end

      it "returns the contract" do
        expect(product_event.contract).to eq(active_contract)
      end
    end

    context "with a contract that starts after the event" do
      before do
        create(:contract, :pending, customer:, external_id: "contract_1", started_at: timestamp + 1.day)
      end

      it "returns the contract running at the event time" do
        expect(product_event.contract).to eq(active_contract)
      end
    end

    context "without any matching contract" do
      let(:active_contract) { nil }

      it "returns nil" do
        expect(product_event.contract).to be_nil
        expect(product_event.customer).to be_nil
      end
    end
  end
end
