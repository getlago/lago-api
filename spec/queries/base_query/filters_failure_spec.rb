# frozen_string_literal: true

require "rails_helper"

RSpec.describe BaseQuery::FiltersFailure do
  subject(:failure) { described_class.new(BaseResult.new, contract_errors:) }

  let(:contract_errors) { Queries::CustomersQueryFiltersContract.new.call(filters).errors }
  let(:filters) { {account_type: %w[bogus customer other], has_customer_type: "maybe"} }

  it "is a validation failure with the messages of the contract" do
    expect(failure).to be_a(BaseService::ValidationFailure)
    expect(failure.messages).to eq(
      account_type: {0 => ["must be one of: customer, partner"], 2 => ["must be one of: customer, partner"]},
      has_customer_type: ["must be one of: true, false"]
    )
  end

  describe "#filters" do
    it "returns the values received and the values allowed of each filter" do
      expect(failure.filters).to eq(
        account_type: {invalid_values: %w[bogus other], allowed_values: %w[customer partner]},
        has_customer_type: {value: "maybe", allowed_values: %w[true false]}
      )
    end

    context "with the same refused value twice" do
      let(:filters) { {account_type: %w[bogus bogus]} }

      it { expect(failure.filters).to eq(account_type: {invalid_values: %w[bogus], allowed_values: %w[customer partner]}) }
    end

    context "with a value of another type" do
      let(:filters) { {currencies: ["EUR", 3]} }

      it { expect(failure.filters).to eq(currencies: {}) }
    end

    context "with a refused value next to a value of another type" do
      let(:filters) { {currencies: ["bogus", 3]} }

      it { expect(failure.filters).to eq(currencies: {}) }
    end

    context "with a filter that an or-schema refuses" do
      let(:contract_errors) { Queries::InvoicesQueryFiltersContract.new.call(filters).errors }
      let(:filters) { {payment_status: "bogus"} }

      it { expect(failure.filters).to eq(payment_status: {}) }
    end

    context "with a filter that a rule refuses" do
      let(:filters) { {has_customer_type: "false", customer_type: "company"} }

      it { expect(failure.filters).to eq(customer_type: {}) }
    end
  end
end
