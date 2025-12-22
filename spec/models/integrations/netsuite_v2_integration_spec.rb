# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::NetsuiteV2Integration do
  subject(:netsuite_v2_integration) { build(:netsuite_v2_integration) }

  it { is_expected.to validate_presence_of(:name) }

  describe "validations" do
    it "validates uniqueness of the code" do
      expect(netsuite_v2_integration).to validate_uniqueness_of(:code).scoped_to(:organization_id)
    end
  end

  describe ".client_secret" do
    it "assigns and retrieve a secret pair" do
      netsuite_v2_integration.client_secret = "client_secret"
      expect(netsuite_v2_integration.client_secret).to eq("client_secret")
    end
  end

  describe "account_id" do
    it "assigns and retrieve a setting" do
      netsuite_v2_integration.account_id = "account_id"
      expect(netsuite_v2_integration.account_id).to eq("account_id")
    end

    context "when format is invalid" do
      it "assigns and retrieve a setting with correct format" do
        netsuite_v2_integration.account_id = "  THIS is    account  id  "
        expect(netsuite_v2_integration.account_id).to eq("this-is-account-id")
      end
    end
  end

  describe ".client_id" do
    it "assigns and retrieve a setting" do
      netsuite_v2_integration.client_id = "client_id"
      expect(netsuite_v2_integration.client_id).to eq("client_id")
    end
  end

  describe "#script_endpoint_url" do
    let(:url) { Faker::Internet.url }

    it "assigns and retrieve a setting" do
      netsuite_v2_integration.script_endpoint_url = url
      expect(netsuite_v2_integration.script_endpoint_url).to eq(url)
    end
  end

  describe "#sync_credit_notes" do
    it "assigns and retrieve a setting" do
      netsuite_v2_integration.sync_credit_notes = true
      expect(netsuite_v2_integration.sync_credit_notes).to eq(true)
    end
  end

  describe "#sync_invoices" do
    it "assigns and retrieve a setting" do
      netsuite_v2_integration.sync_invoices = true
      expect(netsuite_v2_integration.sync_invoices).to eq(true)
    end
  end

  describe "#sync_payments" do
    it "assigns and retrieve a setting" do
      netsuite_v2_integration.sync_payments = true
      expect(netsuite_v2_integration.sync_payments).to eq(true)
    end
  end
end
