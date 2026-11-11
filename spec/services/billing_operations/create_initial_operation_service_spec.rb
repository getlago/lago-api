# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingOperations::CreateInitialOperationService do
  subject(:result) { described_class.call(contract_rate_card:, causation_type: "contract_activation") }

  let(:organization) { create(:organization, feature_flags: []) }
  let(:customer) { create(:customer, organization:, timezone: nil) }
  let(:contract) { create(:contract, organization:, customer:, started_at: Time.zone.parse("2026-01-01 00:00:00")) }
  let(:rate_card) { create(:rate_card, organization:, billing_timing: "arrears", proration: false) }

  let(:contract_rate_card) do
    create(
      :contract_rate_card,
      organization:,
      contract:,
      rate_card:,
      effective_date: Date.new(2026, 1, 1),
      billing_anchor_date: Date.new(2026, 1, 1)
    )
  end

  def add_rate(rate_card, effective_from)
    create(
      :rate_card_rate,
      organization:,
      rate_card:,
      effective_from:,
      billing_interval_count: 1,
      billing_interval_unit: "month"
    )
  end

  before do
    add_rate(rate_card, Time.zone.parse("2026-01-01 00:00:00"))
    contract_rate_card
  end

  describe "#call with a contract rate card" do
    let(:product) { create(:product, :fixed, organization:) }
    let(:rate_card) { create(:rate_card, organization:, billing_timing: "arrears", product:) }
    let(:operation_result) do
      described_class.call(contract_rate_card:, causation_type: "contract_activation")
    end

    it "seeds a periodic operation without creating predicted billing segments" do
      expect(organization.product_catalog_enabled?).to be(false)
      expect { operation_result }.to change(BillingOperation, :count).by(1)
      expect(LegacyBillingSegment.count).to eq(0)

      expect(operation_result.billing_operations.sole).to have_attributes(
        action_type: "close_fixed_arrears",
        billing_at: Time.zone.parse("2026-02-01 00:00:00"),
        target_cycle_started_at: Time.zone.parse("2026-01-01 00:00:00")
      )
    end

    context "when the first cycle has a price change" do
      before do
        create(:rate_card_rate, organization:, rate_card:, effective_from: Time.zone.parse("2026-01-15 00:00:00"),
          billing_interval_count: 1, billing_interval_unit: "month")
      end

      it "seeds only the first due slice without predicting a successor" do
        operations = operation_result.billing_operations

        expect(operations.size).to eq(1)
        expect(operations.sole).to have_attributes(
          billing_at: Time.zone.parse("2026-01-15 00:00:00"),
          target_cycle_started_at: Time.zone.parse("2026-01-01 00:00:00")
        )
      end
    end

    it "does not reset a processed seed when scheduling is repeated" do
      seeded = operation_result.billing_operations.sole
      processed_at = Time.zone.parse("2026-03-01 00:00:00")
      seeded.update!(processed_at:)

      expect { described_class.call(contract_rate_card:, causation_type: "contract_activation") }
        .not_to change { seeded.reload.attributes.slice("processed_at", "billing_at") }
    end
  end
end
