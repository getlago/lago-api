# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingEntity, type: :model do
  subject(:billing_entity) { build(:billing_entity) }

  it_behaves_like "paper_trail traceable"

  it { is_expected.to belong_to(:organization) }

  it { is_expected.to have_many(:customers) }
  it { is_expected.to have_many(:invoices) }
  it { is_expected.to have_many(:invoice_custom_section_selections) }
  it { is_expected.to have_many(:selected_invoice_custom_sections).through(:invoice_custom_section_selections) }
  it { is_expected.to have_many(:fees) }
  it { is_expected.to have_many(:subscriptions).through(:customers) }
  it { is_expected.to have_many(:wallets).through(:customers) }
  it { is_expected.to have_many(:wallet_transactions).through(:wallets) }
  it { is_expected.to have_many(:credit_notes).through(:invoices) }

  it { is_expected.to have_one(:applied_dunning_campaign).class_name("DunningCampaign") }

  it { is_expected.to have_many(:applied_taxes).dependent(:destroy) }
  it { is_expected.to have_many(:taxes).through(:applied_taxes) }

  describe "is_default validation" do
    let(:organization) { create :organization }

    it "validates uniqueness of organization_id for is_default excluding deleted and archived records" do
      # by default an organization is built with a default billing entity
      expect(organization.default_billing_entity.discard!).to be true
      archived_record = create(:billing_entity, :default, :archived, organization:)
      expect(archived_record).to be_valid

      record_1 = create(:billing_entity, :default, organization:)
      expect(record_1).to be_valid

      record_2 = build(:billing_entity, :default, organization:)
      expect(record_2).not_to be_valid
      expect(record_2.errors[:is_default]).to include("value_already_exist")

      record_3 = build(:billing_entity, :default)
      expect(record_3).to be_valid
    end
  end
end
