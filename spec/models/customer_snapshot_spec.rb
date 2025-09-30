# frozen_string_literal: true

require "rails_helper"

RSpec.describe CustomerSnapshot, type: :model do
  subject(:customer_snapshot) { build(:customer_snapshot) }

  it { is_expected.to belong_to(:invoice) }
  it { is_expected.to belong_to(:organization) }

  it { is_expected.to validate_uniqueness_of(:invoice_id).ignoring_case_sensitivity }

  it_behaves_like "paper_trail traceable"

  it { expect(described_class).to be_soft_deletable }

  describe "#shipping_address" do
    let(:customer_snapshot) do
      build(
        :customer_snapshot,
        shipping_address_line1: "123 Shipping St",
        shipping_address_line2: "Apt 456",
        shipping_city: "Shipping City",
        shipping_state: "SC",
        shipping_zipcode: "12345",
        shipping_country: "US"
      )
    end

    it "returns a hash with shipping address information" do
      expected_address = {
        address_line1: "123 Shipping St",
        address_line2: "Apt 456",
        city: "Shipping City",
        state: "SC",
        zipcode: "12345",
        country: "US"
      }

      expect(customer_snapshot.shipping_address).to eq(expected_address)
    end
  end
end
