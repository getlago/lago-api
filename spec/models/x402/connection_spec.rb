# frozen_string_literal: true

require "rails_helper"

RSpec.describe X402::Connection do
  subject(:connection) { build(:x402_connection) }

  describe "enums" do
    it do
      expect(connection).to define_enum_for(:asset).backed_by_column_of_type(:enum).validating.with_values(usdc: "usdc")
    end
  end

  describe "associations" do
    it do
      expect(connection).to belong_to(:organization)
      expect(connection).to have_many(:settlements).class_name("X402::Settlement").with_foreign_key(:x402_connection_id).inverse_of(:x402_connection)
    end
  end

  describe "validations" do
    it do
      expect(connection).to validate_presence_of(:code)
      expect(connection).to validate_presence_of(:name)
      expect(connection).to validate_presence_of(:networks)
    end
  end

  describe "#payout_address_for" do
    it "returns the payout address of the network's chain family" do
      expect(connection.payout_address_for("eip155:84532")).to eq("0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed")
    end
  end
end
