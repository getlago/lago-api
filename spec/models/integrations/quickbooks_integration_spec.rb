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

    describe "realm_id uniqueness" do
      subject(:integration) do
        build(:quickbooks_integration, organization: new_organization, code: "quickbooks_2", settings: {realm_id: new_realm_id})
      end

      let(:organization) { create(:organization) }
      let(:new_organization) { organization }
      let(:stored_realm_id) { "1234567890" }
      let(:new_realm_id) { "1234567890" }
      let(:stored_integration) do
        create(:quickbooks_integration, organization:, code: "quickbooks_1", settings: {realm_id: stored_realm_id})
      end

      before { stored_integration }

      it "is invalid with the realm_id of another QuickBooks integration of the organization" do
        expect(integration).not_to be_valid
        expect(integration.errors[:realm_id]).to eq(["value_already_exist"])
      end

      context "when the realm_id belongs to another organization" do
        let(:new_organization) { create(:organization) }

        it "is valid" do
          expect(integration).to be_valid
        end
      end

      context "when the realm_id is different" do
        let(:new_realm_id) { "9876543210" }

        it "is valid" do
          expect(integration).to be_valid
        end
      end

      context "when the stored integration is validated again with its own realm_id" do
        it "is valid" do
          expect(stored_integration.reload).to be_valid
        end
      end

      context "when both realm_ids are empty strings" do
        let(:stored_realm_id) { "" }
        let(:new_realm_id) { "" }

        it "is valid" do
          expect(integration).to be_valid
        end
      end

      context "when both realm_ids are nil" do
        let(:stored_realm_id) { nil }
        let(:new_realm_id) { nil }

        it "is valid" do
          expect(integration).to be_valid
        end
      end

      context "when a Xero integration of the organization carries the realm_id in its settings" do
        let(:stored_integration) { create(:xero_integration, organization:, settings: {realm_id: stored_realm_id}) }

        it "is valid" do
          expect(integration).to be_valid
        end
      end

      context "when the stored realm_id is a string and the new one an Integer" do
        let(:stored_realm_id) { "123" }
        let(:new_realm_id) { 123 }

        it "is invalid" do
          expect(integration).not_to be_valid
          expect(integration.errors[:realm_id]).to eq(["value_already_exist"])
        end

        # Behind a database proxy, prepared statements are off and the bound value is inlined in the SQL
        it "is invalid without prepared statements" do
          valid = ActiveRecord::Base.connection.unprepared_statement { integration.valid? }

          expect(valid).to eq(false)
          expect(integration.errors[:realm_id]).to eq(["value_already_exist"])
        end
      end
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

  describe "#realm_id_mismatch" do
    it "assigns and retrieve a setting" do
      quickbooks_integration.realm_id_mismatch = true
      quickbooks_integration.save!

      expect(quickbooks_integration.reload.realm_id_mismatch).to eq(true)
    end

    it "returns nil when absent from the settings" do
      quickbooks_integration.save!

      expect(quickbooks_integration.reload.settings).not_to have_key("realm_id_mismatch")
      expect(quickbooks_integration.realm_id_mismatch).to be_nil
    end
  end

  describe "#realm_id_mismatch?" do
    [true, "true"].each do |value|
      it "returns true when realm_id_mismatch is #{value.inspect}" do
        quickbooks_integration.realm_id_mismatch = value

        expect(quickbooks_integration.realm_id_mismatch?).to eq(true)
      end
    end

    [false, "false", nil, "yes", 1].each do |value|
      it "returns false when realm_id_mismatch is #{value.inspect}" do
        quickbooks_integration.realm_id_mismatch = value

        expect(quickbooks_integration.realm_id_mismatch?).to eq(false)
      end
    end

    it "returns false when realm_id_mismatch is absent from the settings" do
      quickbooks_integration.settings = {realm_id: "1234567890"}

      expect(quickbooks_integration.realm_id_mismatch?).to eq(false)
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

  describe "unique company index" do
    let(:organization) { create(:organization) }

    # Saved without validations, so only the database can refuse the row.
    def insert_row(organization_id:, code:, realm_id:, factory: :quickbooks_integration)
      build(factory, organization_id:, code:, settings: {realm_id:}).save!(validate: false)
    end

    before { insert_row(organization_id: organization.id, code: "quickbooks_1", realm_id: "1234567890") }

    it "rejects a second QuickBooks row with the same organization and company" do
      expect { insert_row(organization_id: organization.id, code: "quickbooks_2", realm_id: "1234567890") }
        .to raise_error(ActiveRecord::RecordNotUnique, /index_integrations_on_organization_id_and_quickbooks_realm_id/)
    end

    it "accepts the same company in another organization" do
      expect { insert_row(organization_id: create(:organization).id, code: "quickbooks_1", realm_id: "1234567890") }
        .not_to raise_error
    end

    it "accepts two QuickBooks rows without a company id" do
      insert_row(organization_id: organization.id, code: "quickbooks_2", realm_id: nil)

      expect { insert_row(organization_id: organization.id, code: "quickbooks_3", realm_id: nil) }.not_to raise_error
    end

    it "ignores other integration types" do
      expect { insert_row(organization_id: organization.id, code: "xero_1", realm_id: "1234567890", factory: :xero_integration) }
        .not_to raise_error
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
