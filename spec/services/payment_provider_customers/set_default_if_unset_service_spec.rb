# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviderCustomers::SetDefaultIfUnsetService do
  subject(:set_service) { described_class.call(customer:) }

  let(:organization) { create(:organization) }
  let(:customer) do
    create(:customer, organization:, payment_provider: "stripe", payment_provider_code: "stripe_1")
  end

  before { create(:stripe_provider, organization:, code: "stripe_1") }

  context "when the customer holds no connection at all" do
    it "succeeds without flagging anything" do
      expect(set_service).to be_success
      expect(set_service.payment_provider_customer).to be_nil
    end
  end

  context "when the resolved connection is the only one" do
    let(:connection) { create(:stripe_customer, customer:, organization:) }

    before { connection }

    it "flags it as default" do
      expect(set_service).to be_success
      expect(connection.reload).to be_is_default
    end
  end

  context "when another connection already holds the default" do
    let(:connection) { create(:stripe_customer, customer:, organization:) }
    let(:chosen_default) { create(:gocardless_customer, customer:, organization:, is_default: true) }

    before do
      connection
      chosen_default
    end

    it "leaves the default where it is" do
      expect(set_service).to be_success
      expect(chosen_default.reload).to be_is_default
      expect(connection.reload).not_to be_is_default
    end
  end

  context "when another connection exists but holds no default" do
    let(:connection) { create(:stripe_customer, customer:, organization:) }
    let(:other) { create(:gocardless_customer, customer:, organization:, is_default: false) }

    before do
      connection
      other
    end

    it "flags the resolved connection, since nothing else claims the default" do
      expect(set_service).to be_success
      expect(connection.reload).to be_is_default
    end
  end

  context "without a customer" do
    let(:customer) { nil }

    it "returns a not found failure" do
      expect(set_service).not_to be_success
      expect(set_service.error.error_code).to eq("customer_not_found")
    end
  end
end
