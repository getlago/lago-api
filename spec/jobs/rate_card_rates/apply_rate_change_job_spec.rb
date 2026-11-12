# frozen_string_literal: true

require "rails_helper"

RSpec.describe RateCardRates::ApplyRateChangeJob do
  subject(:perform_job) { described_class.perform_now(rate.id) }

  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:product) { create(:product, :fixed, organization:) }
  let(:rate_card) { create(:rate_card, organization:, product:) }
  let(:rate) { create(:rate_card_rate, organization:, rate_card:) }
  let(:customer) { create(:customer, organization:) }
  let(:contract) { create(:contract, organization:, customer:) }
  let(:second_contract) { create(:contract, organization:, customer:) }
  let(:other_customer) { create(:customer, organization:) }
  let(:other_contract) { create(:contract, organization:, customer: other_customer) }
  let(:terminated_contract) { create(:contract, :terminated, organization:) }
  let(:pending_contract) { create(:contract, :pending, organization:) }
  let(:foreign_contract) { create(:contract) }
  let(:discarded_contract) { create(:contract, organization:) }

  before do
    [contract, second_contract, other_contract, terminated_contract, pending_contract].each do |applied_contract|
      create(:contract_rate_card, organization:, contract: applied_contract, rate_card:)
    end
    create(:contract_rate_card, organization: foreign_contract.organization, contract: foreign_contract, rate_card:)
    create(:contract_rate_card, organization:, contract: discarded_contract, rate_card:, deleted_at: Time.current)
  end

  it "fans out once per eligible customer, within the organization" do
    expect { perform_job }.to have_enqueued_job(BillingOperations::ApplyRateChangeJob).exactly(2).times
    expect(BillingOperations::ApplyRateChangeJob).to have_been_enqueued.with(customer.id, rate.id)
    expect(BillingOperations::ApplyRateChangeJob).to have_been_enqueued.with(other_customer.id, rate.id)
  end

  context "when the rate was deleted" do
    before { rate.discard! }

    it "does nothing" do
      expect { perform_job }.not_to have_enqueued_job(BillingOperations::ApplyRateChangeJob)
    end
  end

  context "when the card was deleted" do
    before do
      rate
      rate_card.discard!
    end

    it "does nothing" do
      expect { perform_job }.not_to have_enqueued_job(BillingOperations::ApplyRateChangeJob)
    end
  end

  context "when the catalog is disabled" do
    before { organization.disable_feature_flag!(:product_catalog) }

    it "still dispatches rate changes to the affected customers" do
      expect { perform_job }.to have_enqueued_job(BillingOperations::ApplyRateChangeJob).exactly(2).times
    end
  end

  context "when the product is metered" do
    let(:product) { create(:product, organization:) }

    it "fans out once per eligible customer" do
      expect { perform_job }.to have_enqueued_job(BillingOperations::ApplyRateChangeJob).exactly(2).times
      expect(BillingOperations::ApplyRateChangeJob).to have_been_enqueued.with(customer.id, rate.id)
      expect(BillingOperations::ApplyRateChangeJob).to have_been_enqueued.with(other_customer.id, rate.id)
    end
  end
end
