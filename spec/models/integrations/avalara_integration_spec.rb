# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::AvalaraIntegration, type: :model do
  subject(:avalara_integration) { build(:avalara_integration) }

  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_presence_of(:connection_id) }
  it { is_expected.to validate_presence_of(:account_id) }
  it { is_expected.to validate_presence_of(:license_key) }
  it { is_expected.to have_many(:error_details) }

  describe "validations" do
    it "validates uniqueness of the code" do
      expect(avalara_integration).to validate_uniqueness_of(:code).scoped_to(:organization_id)
    end
  end

  describe ".license_key" do
    it "assigns and retrieve an license_key" do
      avalara_integration.license_key = "123abc456"
      expect(avalara_integration.license_key).to eq("123abc456")
    end
  end

  describe ".connection_id" do
    it "assigns and retrieve a secret pair" do
      avalara_integration.connection_id = "connection_id"
      expect(avalara_integration.connection_id).to eq("connection_id")
    end
  end

  describe ".account_id" do
    it "assigns and retrieve a secret pair" do
      avalara_integration.account_id = "account_id"
      expect(avalara_integration.account_id).to eq("account_id")
    end
  end
end
