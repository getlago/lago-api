# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::QuickbooksIntegration do
  subject(:quickbooks_integration) { build(:quickbooks_integration) }

  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_presence_of(:connection_id) }

  describe "validations" do
    it "validates uniqueness of the code" do
      expect(quickbooks_integration).to validate_uniqueness_of(:code).scoped_to(:organization_id)
    end

    it "is valid with a connection_id" do
      expect(quickbooks_integration).to be_valid
    end

    it "is invalid without a connection_id" do
      quickbooks_integration.connection_id = nil

      expect(quickbooks_integration).not_to be_valid
      expect(quickbooks_integration.errors[:connection_id]).to eq(["value_is_mandatory"])
    end
  end

  describe ".connection_id" do
    it "assigns and retrieve a secret pair" do
      quickbooks_integration.connection_id = "connection_id"
      expect(quickbooks_integration.connection_id).to eq("connection_id")
    end

    it "stores the value in the secrets and not in the settings" do
      quickbooks_integration.connection_id = "connection_id"
      quickbooks_integration.save!
      quickbooks_integration.reload

      expect(JSON.parse(quickbooks_integration.secrets)).to eq({"connection_id" => "connection_id"})
      expect(quickbooks_integration.settings).not_to have_key("connection_id")
      expect(quickbooks_integration.settings.values).not_to include("connection_id")
    end

    it "encrypts the secrets column" do
      quickbooks_integration.connection_id = "connection_id"
      quickbooks_integration.save!

      expect(quickbooks_integration.ciphertext_for(:secrets)).not_to include("connection_id")
    end
  end

  describe "#sync_credit_notes" do
    it "assigns and retrieve a setting" do
      quickbooks_integration.sync_credit_notes = true
      quickbooks_integration.save!

      expect(quickbooks_integration.reload.sync_credit_notes).to eq(true)
    end
  end

  describe "#sync_invoices" do
    it "assigns and retrieve a setting" do
      quickbooks_integration.sync_invoices = true
      quickbooks_integration.save!

      expect(quickbooks_integration.reload.sync_invoices).to eq(true)
    end
  end

  describe "#sync_payments" do
    it "assigns and retrieve a setting" do
      quickbooks_integration.sync_payments = true
      quickbooks_integration.save!

      expect(quickbooks_integration.reload.sync_payments).to eq(true)
    end
  end

  describe "#realm_id" do
    it "assigns and retrieve a setting" do
      quickbooks_integration.realm_id = "9876543210"
      quickbooks_integration.save!

      expect(quickbooks_integration.reload.realm_id).to eq("9876543210")
    end
  end

  describe "#sandbox" do
    it "assigns and retrieve a setting" do
      quickbooks_integration.sandbox = true
      quickbooks_integration.save!

      expect(quickbooks_integration.reload.sandbox).to eq(true)
    end
  end

  describe "#sandbox?" do
    [true, "true"].each do |value|
      it "returns true when sandbox is #{value.inspect}" do
        quickbooks_integration.sandbox = value

        expect(quickbooks_integration.sandbox?).to eq(true)
      end
    end

    [false, "false", nil, "False", "no", 1].each do |value|
      it "returns false when sandbox is #{value.inspect}" do
        quickbooks_integration.sandbox = value

        expect(quickbooks_integration.sandbox?).to eq(false)
      end
    end

    it "returns false when sandbox is absent from the settings" do
      quickbooks_integration.settings = {realm_id: "1234567890"}

      expect(quickbooks_integration.sandbox?).to eq(false)
    end
  end

  describe "#external_id_key" do
    it "returns id" do
      expect(quickbooks_integration.external_id_key).to eq("id")
    end
  end

  describe "#provider_key" do
    it "returns quickbooks" do
      expect(quickbooks_integration.provider_key).to eq("quickbooks")
    end

    it "returns quickbooks for a sandbox integration too" do
      quickbooks_integration.sandbox = true

      expect(quickbooks_integration.provider_key).to eq("quickbooks")
    end
  end

  describe "organization.quickbooks_integrations" do
    let(:organization) { create(:organization) }
    let(:quickbooks_integration) { create(:quickbooks_integration, organization:) }

    before do
      quickbooks_integration
      create(:xero_integration, organization:)
      create(:netsuite_integration, organization:)
    end

    it "returns the QuickBooks integration and no other integration type" do
      expect(organization.quickbooks_integrations).to eq([quickbooks_integration])
    end
  end
end
