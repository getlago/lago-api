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
  it { is_expected.to belong_to(:applied_dunning_campaign).class_name("DunningCampaign").optional }

  it { is_expected.to have_many(:applied_taxes).dependent(:destroy) }
  it { is_expected.to have_many(:taxes).through(:applied_taxes) }

  describe "code validation" do
    let(:organization) { create :organization }

    it "validates uniqueness of organization_id for code excluding deleted and archived records" do
      record_1 = create(:billing_entity, organization: organization)
      expect(record_1).to be_valid

      record_2 = build(:billing_entity, organization: organization, code: record_1.code)
      expect(record_2).not_to be_valid
      expect(record_2.errors[:code]).to include("value_already_exist")

      record_3 = create(:billing_entity, code: record_1.code)
      expect(record_3).to be_valid

      record_1.discard!
      record_4 = build(:billing_entity, organization: organization, code: record_1.code)
      expect(record_4).to be_valid

      record_1.undiscard!
      record_1.update(archived_at: Time.current)
      record_5 = build(:billing_entity, organization: organization, code: record_1.code)
      expect(record_5).to be_valid
    end
  end

  describe "Validations" do
    let(:billing_entity) { build(:billing_entity) }

    it "is valid with valid attributes" do
      expect(billing_entity).to be_valid
    end

    it "is not valid without name" do
      billing_entity.name = nil
      expect(billing_entity).not_to be_valid
    end

    it "is invalid with invalid email" do
      billing_entity.email = "foo.bar"
      expect(billing_entity).not_to be_valid
    end

    it "is invalid with invalid country" do
      billing_entity.country = "ZWX"
      expect(billing_entity).not_to be_valid

      billing_entity.country = ""
      expect(billing_entity).not_to be_valid
    end

    it "validates the language code" do
      billing_entity.document_locale = nil
      expect(billing_entity).not_to be_valid

      billing_entity.document_locale = "en"
      expect(billing_entity).to be_valid

      billing_entity.document_locale = "foo"
      expect(billing_entity).not_to be_valid

      billing_entity.document_locale = ""
      expect(billing_entity).not_to be_valid
    end

    it "is invalid with invalid invoice footer" do
      billing_entity.invoice_footer = SecureRandom.alphanumeric(601)
      expect(billing_entity).not_to be_valid
    end

    it "is valid with logo" do
      billing_entity.logo.attach(
        io: File.open(Rails.root.join("spec/factories/images/logo.png")),
        content_type: "image/png",
        filename: "logo"
      )
      expect(billing_entity).to be_valid
    end

    it "is invalid with too big logo" do
      billing_entity.logo.attach(
        io: File.open(Rails.root.join("spec/factories/images/big_sized_logo.jpg")),
        content_type: "image/jpeg",
        filename: "logo"
      )
      expect(billing_entity).not_to be_valid
    end

    it "is invalid with unsupported logo content type" do
      billing_entity.logo.attach(
        io: File.open(Rails.root.join("spec/factories/images/logo.gif")),
        content_type: "image/gif",
        filename: "logo"
      )
      expect(billing_entity).not_to be_valid
    end

    it "is invalid with invalid timezone" do
      billing_entity.timezone = "foo"
      expect(billing_entity).not_to be_valid
    end

    it "is valid with email_settings" do
      billing_entity.email_settings = ["invoice.finalized", "credit_note.created"]
      expect(billing_entity).to be_valid
    end

    it "is invalid with non permitted email_settings value" do
      billing_entity.email_settings = ["email.not_permitted"]

      expect(billing_entity).not_to be_valid
      expect(billing_entity.errors.first.attribute).to eq(:email_settings)
      expect(billing_entity.errors.first.type).to eq(:unsupported_value)
    end

    it "dont allow finalize_zero_amount_invoice with null value" do
      expect(billing_entity.finalize_zero_amount_invoice).to eq true
      billing_entity.finalize_zero_amount_invoice = nil

      expect(billing_entity).not_to be_valid
    end
  end

  describe "#save" do
    subject { billing_entity.save! }

    context "with a new record" do
      let(:billing_entity) { build(:billing_entity) }

      it "sets document number prefix of billing_entity" do
        subject

        expect(billing_entity.document_number_prefix)
          .to eq "#{billing_entity.name.first(3).upcase}-#{billing_entity.id.last(4).upcase}"
      end

      context "when document number prefix is already set" do
        it "does not change existing document number prefix of billing_entity" do
          billing_entity.document_number_prefix = "ABC-1234"
          subject

          expect(billing_entity.document_number_prefix).to eq "ABC-1234"
        end
      end
    end

    context "with a persisted record" do
      let(:billing_entity) { create(:billing_entity) }

      it "does not change document number prefix of billing_entity" do
        expect { subject }.not_to change(billing_entity, :document_number_prefix)
      end
    end
  end
end
