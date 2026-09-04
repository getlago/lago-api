# frozen_string_literal: true

require "rails_helper"

RSpec.describe RealtimeUsage::RefreshableCustomersService do
  subject(:service) { described_class.call(triggers:) }

  include_context "with realtime usage availability"

  let(:organization) do
    create(:organization, clickhouse_events_store: true, feature_flags: ["realtime_usage"])
  end
  let(:customer) { create(:customer, organization:) }
  let!(:wallet) { create(:wallet, customer:, organization:) }

  let(:triggers) do
    {customer.id => {organization_id: organization.id, customer_id: customer.id, offset: 0}}
  end

  describe "#call" do
    it "returns the customer a refresh could act on" do
      expect(service.customers).to eq(customer.id => customer)
    end

    # The wallet ids are what let the job run for a customer the sweep has not flagged.
    it "returns the customer's active wallet ids" do
      expect(service.active_wallet_ids).to eq(customer.id => [wallet.id])
    end

    it "excludes a customer whose wallets are all terminated" do
      customer.wallets.update_all(status: :terminated) # rubocop:disable Rails/SkipsModelValidations

      expect(service.customers).to be_empty
    end

    it "excludes a customer with a tax error" do
      create(:error_detail, owner: customer, organization:, error_code: :tax_error)

      expect(service.customers).to be_empty
    end

    context "when the organization is outside the realtime usage rollout" do
      let(:organization) { create(:organization, clickhouse_events_store: true) }

      it "excludes its customers" do
        expect(service.customers).to be_empty
      end
    end
  end
end
