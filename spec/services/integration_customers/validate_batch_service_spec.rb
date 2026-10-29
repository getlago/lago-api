# frozen_string_literal: true

require "rails_helper"

RSpec.describe IntegrationCustomers::ValidateBatchService do
  subject(:result) { described_class.call(integration_customers:) }

  let(:integration_customers) { nil }

  it "accepts omitted integration customers" do
    expect(result).to be_success
  end

  context "with an empty list" do
    let(:integration_customers) { [] }

    it "accepts the list" do
      expect(result).to be_success
    end
  end

  IntegrationCustomers::BaseCustomer::CUSTOMER_TYPES.each_key do |integration_type|
    context "with #{integration_type} as integration type" do
      let(:integration_customers) { [{"integration_type" => integration_type, "integration_code" => "code"}] }

      it "accepts the type" do
        expect(result).to be_success
      end
    end
  end

  [nil, "bogus", "entra_id", "progressive_billing"].each do |integration_type|
    context "with #{integration_type.inspect} as integration type" do
      let(:integration_customers) do
        [{integration_type: "netsuite", integration_code: "netsuite"}, {integration_type:, integration_code: "code"}.compact]
      end

      it "returns a validation error" do
        expect(result).to be_failure
        expect(result.error.messages).to eq(integration_type: ["value_is_invalid"])
      end
    end
  end
end
