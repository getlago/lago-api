# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sources::CustomerActiveContractsCount do
  subject(:counts) { described_class.new.fetch(customer_ids) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:other_customer) { create(:customer, organization:) }
  let(:customer_ids) { [customer.id, other_customer.id] }

  describe "#fetch" do
    before do
      create_pair(:contract, customer:)
      create(:contract, :pending, customer:)
      create(:contract, :terminated, customer:)
      create(:contract, :canceled, customer:)
      create(:contract, :pending, customer: other_customer)
      create(:contract)
    end

    it "counts the active contracts of each customer, zero when there is none" do
      expect(counts).to eq([2, 0])
    end
  end
end
