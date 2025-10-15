# frozen_string_literal: true

require "rails_helper"

RSpec.describe Organization do
  subject(:organization) do
    described_class.new(
      name: "PiedPiper",
      email: "foo@bar.com",
      country: "FR",
      invoice_footer: "this is an invoice footer"
    )
  end

  describe "associations" do
    it do
      expect(subject).to have_many(:stripe_payment_providers)
      expect(subject).to have_many(:gocardless_payment_providers)
      expect(subject).to have_many(:adyen_payment_providers)

      expect(subject).to have_many(:api_keys)
      expect(subject).to have_many(:billing_entities).conditions(archived_at: nil)
      expect(subject).to have_many(:all_billing_entities).class_name("BillingEntity")
      expect(subject).to have_many(:pricing_units)
      expect(subject).to have_many(:customers)
      expect(subject).to have_many(:subscriptions)
      expect(subject).to have_many(:credit_notes)
      expect(subject).to have_many(:invoices)
      expect(subject).to have_many(:fees)
      expect(subject).to have_many(:applied_coupons)
      expect(subject).to have_many(:wallets)
      expect(subject).to have_many(:wallet_transactions)
      expect(subject).to have_one(:default_billing_entity).class_name("BillingEntity")
      expect(subject).to have_many(:webhook_endpoints)
      expect(subject).to have_many(:webhooks)
      expect(subject).to have_many(:hubspot_integrations)
      expect(subject).to have_many(:netsuite_integrations)
      expect(subject).to have_many(:xero_integrations)
      expect(subject).to have_one(:salesforce_integration)
      expect(subject).to have_many(:data_exports)
      expect(subject).to have_many(:dunning_campaigns)
      expect(subject).to have_many(:daily_usages)
      expect(subject).to have_many(:invoice_custom_sections)
      expect(subject).to have_many(:ai_conversations)
      expect(subject).to have_many(:manual_invoice_custom_sections).conditions(section_type: "manual")
      expect(subject).to have_many(:payment_methods)
      expect(subject).to have_many(:system_generated_invoice_custom_sections).conditions(section_type: "system_generated")

      expect(subject).to have_many(:features).class_name("Entitlement::Feature")
      expect(subject).to have_many(:privileges).class_name("Entitlement::Privilege")
      expect(subject).to have_many(:entitlements).class_name("Entitlement::Entitlement")
      expect(subject).to have_many(:entitlement_values).class_name("Entitlement::EntitlementValue")
      expect(subject).to have_many(:subscription_feature_removals).class_name("Entitlement::SubscriptionFeatureRemoval")

      expect(subject).to have_one(:applied_dunning_campaign).conditions(applied_to_organization: true)
    end
  end

  describe "Clickhouse associations", clickhouse: true do
    it { is_expected.to have_many(:activity_logs).class_name("Clickhouse::ActivityLog") }
  end

  it "sets the default value to true" do
    expect(organization.finalize_zero_amount_invoice).to eq true
  end

  it_behaves_like "paper_trail traceable"

  describe "Validations" do
    it do
      expect(subject).to validate_inclusion_of(:default_currency).in_array(described_class.currency_list)
    end

    it "is valid with valid attributes" do
      expect(organization).to be_valid
    end

    it "is not valid without name" do
      organization.name = nil

      expect(organization).not_to be_valid
    end

    it "is invalid with invalid email" do
      organization.email = "foo.bar"

      expect(organization).not_to be_valid
    end

    it "is invalid with invalid country" do
      organization.country = "ZWX"

      expect(organization).not_to be_valid

      organization.country = ""

      expect(organization).not_to be_valid
    end

    it "validates the language code" do
      organization.document_locale = nil
      expect(organization).not_to be_valid

      organization.document_locale = "en"
      expect(organization).to be_valid

      organization.document_locale = "foo"
      expect(organization).not_to be_valid

      organization.document_locale = ""
      expect(organization).not_to be_valid
    end

    it "is invalid with invalid invoice footer" do
      organization.invoice_footer = SecureRandom.alphanumeric(601)

      expect(organization).not_to be_valid
    end

    it "is valid with logo" do
      organization.logo.attach(
        io: File.open(Rails.root.join("spec/factories/images/logo.png")),
        content_type: "image/png",
        filename: "logo"
      )

      expect(organization).to be_valid
    end

    it "is invalid with too big logo" do
      organization.logo.attach(
        io: File.open(Rails.root.join("spec/factories/images/big_sized_logo.jpg")),
        content_type: "image/jpeg",
        filename: "logo"
      )

      expect(organization).not_to be_valid
    end

    it "is invalid with unsupported logo content type" do
      organization.logo.attach(
        io: File.open(Rails.root.join("spec/factories/images/logo.gif")),
        content_type: "image/gif",
        filename: "logo"
      )

      expect(organization).not_to be_valid
    end

    it "is invalid with invalid timezone" do
      organization.timezone = "foo"

      expect(organization).not_to be_valid
    end

    it "is valid with email_settings" do
      organization.email_settings = ["invoice.finalized", "credit_note.created", "payment_receipt.created"]

      expect(organization).to be_valid
    end

    it "is invalid with non permitted email_settings value" do
      organization.email_settings = ["email.not_permitted"]

      expect(organization).not_to be_valid
      expect(organization.errors.first.attribute).to eq(:email_settings)
      expect(organization.errors.first.type).to eq(:unsupported_value)
    end

    it "dont allow finalize_zero_amount_invoice with null value" do
      expect(organization.finalize_zero_amount_invoice).to eq true
      organization.finalize_zero_amount_invoice = nil

      expect(organization).not_to be_valid
    end

    describe "of hmac key uniqueness" do
      before { create(:organization) }

      it { is_expected.to validate_uniqueness_of(:hmac_key) }
    end

    describe "of hmac key presence" do
      subject { organization }

      context "with a new record" do
        let(:organization) { build(:organization) }

        it { is_expected.not_to validate_presence_of(:hmac_key) }
      end

      context "with a persisted record" do
        let(:organization) { create(:organization) }

        it { is_expected.to validate_presence_of(:hmac_key) }
      end
    end

    describe "of premium_integrations inclusion" do
      context "when it includes an invalid integration" do
        subject(:organization) { build(:organization, premium_integrations: ["invalid_integration"]) }

        it do
          expect(subject).not_to be_valid
          expect(organization.errors.to_hash).to eq(premium_integrations: ["value_is_invalid"])
        end
      end

      context "when it includes a valid integration" do
        subject(:organization) { build(:organization, :premium) }

        it { is_expected.to be_valid }
      end
    end
  end

  describe "#save" do
    subject { organization.save! }

    context "with a new record" do
      let(:organization) { build(:organization) }
      let(:used_hmac_key) { create(:organization).hmac_key }
      let(:unique_hmac_key) { SecureRandom.uuid }

      before do
        allow(SecureRandom).to receive(:uuid).and_return(used_hmac_key, unique_hmac_key)
      end

      it "sets document number prefix of organization" do
        subject

        expect(organization.document_number_prefix)
          .to eq "#{organization.name.first(3).upcase}-#{organization.id.last(4).upcase}"
      end

      it "sets unique hmac key" do
        expect { subject }.to change(organization, :hmac_key).to unique_hmac_key
      end
    end

    context "with a persisted record" do
      let(:organization) { create(:organization) }

      it "does not change document number prefix of organization" do
        expect { subject }.not_to change(organization, :document_number_prefix)
      end

      it "does not change the hmac key" do
        expect { subject }.not_to change(organization, :hmac_key)
      end
    end
  end

  describe ".with_any_premium_integrations" do
    it do
      create(:organization, premium_integrations: %w[okta xero from_email])
      create(:organization, premium_integrations: %w[okta])
      create(:organization, premium_integrations: %w[salesforce from_email])
      create(:organization, premium_integrations: %w[salesforce])

      expect(described_class.with_any_premium_integrations([]).count).to eq(0)
      expect(described_class.with_any_premium_integrations("okta").count).to eq(2)
      expect(described_class.with_any_premium_integrations(%w[okta from_email]).count).to eq(3)
      expect(described_class.with_any_premium_integrations(%w[okta salesforce]).count).to eq(4)
    end
  end

  describe "Premium integrations scopes" do
    it "returns the organization if the premium integration is enabled" do
      Organization::PREMIUM_INTEGRATIONS.each do |integration|
        expect(described_class.send("with_#{integration}_support")).to be_empty
        organization.update!(premium_integrations: [integration])
        expect(described_class.send("with_#{integration}_support")).to eq([organization])
        organization.update!(premium_integrations: [])
      end
    end

    it "does not return the organization for another premium integration" do
      organization.update!(premium_integrations: ["progressive_billing"])
      expect(described_class.with_okta_support).to be_empty
      expect(described_class.with_progressive_billing_support).to eq([organization])
    end
  end

  describe "#premium_integrations_enabled?" do
    described_class::PREMIUM_INTEGRATIONS.each do |integration|
      it_behaves_like "organization premium feature", integration
    end
  end

  describe "#can_create_billing_entity?" do
    subject { organization.can_create_billing_entity? }

    around { |test| lago_premium!(&test) }

    context "when no premium multi entities integration is enabled" do
      it { is_expected.to eq(true) }

      context "when organization has one active billing entity" do
        before do
          create(:billing_entity, organization:)
        end

        it { is_expected.to eq(false) }
      end
    end

    context "when the premium multi_entities_pro integration is enabled" do
      before do
        organization.update!(premium_integrations: ["multi_entities_pro"])
      end

      it { is_expected.to eq(true) }

      context "when the organization has reached the limit" do
        before do
          create_list(:billing_entity, 2, organization:)
        end

        it { is_expected.to eq(false) }
      end

      context "when organization has archived billing entities" do
        before do
          create_list(:billing_entity, 2, :archived, organization:)
        end

        it { is_expected.to eq true }
      end
    end

    context "when the premium multi_entities_enterprise integration is enabled" do
      before do
        organization.update!(premium_integrations: ["multi_entities_enterprise"])
      end

      it { is_expected.to eq(true) }

      context "when the organization has some billing entities" do
        before do
          create_list(:billing_entity, 2, organization:)
        end

        it { is_expected.to eq(true) }
      end
    end
  end

  describe "#using_lifetime_usage?" do
    around { |test| lago_premium!(&test) }

    it do
      expect(build(:organization, premium_integrations: ["lifetime_usage"])).to be_using_lifetime_usage
      expect(build(:organization, premium_integrations: ["progressive_billing"])).to be_using_lifetime_usage
      expect(build(:organization, premium_integrations: ["lifetime_usage", "progressive_billing"])).to be_using_lifetime_usage
      expect(build(:organization, premium_integrations: [])).not_to be_using_lifetime_usage
      expect(build(:organization, premium_integrations: ["okta"])).not_to be_using_lifetime_usage
    end
  end

  describe "#admins" do
    subject { organization.admins }

    let(:organization) { create(:organization) }
    let(:scoped) { create(:membership, organization:).user }

    before do
      scoped
      create(:membership)
      create(:membership, organization:, role: [:manager, :finance].sample)
      create(:membership, organization:, role: :admin, status: :revoked)
    end

    it "returns admins of the organization" do
      expect(subject).to contain_exactly scoped
    end
  end

  describe "#from_email_address" do
    it "returns the env var email" do
      expect(organization.from_email_address).to eq("noreply@getlago.com")
    end

    context "when organization from_email integration is enabled" do
      around { |test| lago_premium!(&test) }

      it "returns the organization email" do
        organization.update!(premium_integrations: ["from_email"])
        expect(organization.from_email_address).to eq(organization.email)
      end
    end
  end

  describe "#default_billing_entity" do
    subject(:default_billing_entity) { organization.default_billing_entity }

    let(:organization) { create(:organization, billing_entities: []) }

    context "when the organization has no billing entities" do
      it { is_expected.to eq(nil) }
    end

    context "when the organization has one billing entity" do
      let(:billing_entity) { create(:billing_entity, organization:) }

      before { billing_entity }

      it { is_expected.to eq(billing_entity) }
    end

    context "when the organization has multiple billing entities" do
      let(:billing_entity_1) { create(:billing_entity, organization:, created_at: 1.day.ago) }
      let(:billing_entity_2) { create(:billing_entity, organization:, created_at: 2.days.ago) }
      let(:billing_entity_3) { create(:billing_entity, organization:, created_at: 3.days.ago, archived_at: Time.current) }

      before do
        billing_entity_1
        billing_entity_2
        billing_entity_3
      end

      it "returns the oldest active billing entity" do
        expect(default_billing_entity).to eq(billing_entity_2)
      end
    end
  end

  describe "#failed_tax_invoices_count" do
    subject(:failed_tax_invoices_count) { organization.failed_tax_invoices_count }

    let(:organization) { create(:organization) }
    let(:invoice1) { create(:invoice, organization:, status: :failed) }
    let(:invoice2) { create(:invoice, organization:, status: :failed) }
    let(:invoice3) { create(:invoice, organization:, status: :draft) }
    let(:error_detail1) do
      create(
        :error_detail,
        owner: invoice1,
        organization:,
        error_code: :tax_error,
        details: {
          tax_error: "productExternalIdUnknown"
        }
      )
    end
    let(:error_detail2) do
      create(
        :error_detail,
        owner: invoice2,
        organization:,
        error_code: :tax_error,
        details: {
          tax_error: "productExternalIdUnknown"
        }
      )
    end

    before do
      invoice1
      invoice2
      invoice3
      error_detail1
      error_detail2
    end

    it "returns the count of failed tax invoices" do
      expect(failed_tax_invoices_count).to eq(2)
    end
  end

  describe "default_currency" do
    let(:organization) { create(:organization, default_currency: "USD") }
    let(:billing_entity) { create(:billing_entity, organization:, default_currency: "EUR") }

    before do
      organization.default_billing_entity.update(default_currency: "GBP")
      billing_entity
    end

    it "ignores existing value in organization and uses value from default_billing_entity" do
      expect(organization.default_currency).to eq("GBP")
    end
  end

  describe "timezone" do
    let(:organization) { create(:organization, timezone: "UTC") }
    let(:billing_entity) { create(:billing_entity, organization:, timezone: "America/New_York") }

    before do
      organization.default_billing_entity.update(timezone: "Europe/London")
      billing_entity
    end

    it "ignores existing value in organization and uses value from default_billing_entity" do
      expect(organization.timezone).to eq("Europe/London")
    end
  end

  describe "postgres_events_store?" do
    let(:organization) { create(:organization, clickhouse_events_store: true) }

    it "returns true if postgres_events_store is true" do
      expect(organization).not_to be_postgres_events_store
      expect(organization).to be_clickhouse_events_store
    end

    context "when clickhouse_events_store is false" do
      let(:organization) { create(:organization, clickhouse_events_store: false) }

      it "returns false" do
        expect(organization).not_to be_clickhouse_events_store
        expect(organization).to be_postgres_events_store
      end
    end
  end
end
