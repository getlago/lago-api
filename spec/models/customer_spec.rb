# frozen_string_literal: true

require "rails_helper"

RSpec.describe Customer do
  subject(:customer) { create(:customer) }

  let(:organization) { create(:organization) }
  let(:billing_entity) { create(:billing_entity, organization:) }

  it_behaves_like "paper_trail traceable"

  it { is_expected.to belong_to(:applied_dunning_campaign).optional }
  it { is_expected.to belong_to(:billing_entity).optional }
  it { is_expected.to have_many(:daily_usages) }

  it { is_expected.to have_many(:integration_customers).dependent(:destroy) }
  it { is_expected.to have_many(:payment_methods) }
  it { is_expected.to have_many(:payment_requests) }

  it { is_expected.to have_one(:netsuite_customer) }
  it { is_expected.to have_one(:anrok_customer) }
  it { is_expected.to have_one(:xero_customer) }
  it { is_expected.to have_one(:hubspot_customer) }
  it { is_expected.to have_one(:salesforce_customer) }

  it { is_expected.to have_many(:applied_invoice_custom_sections).class_name("Customer::AppliedInvoiceCustomSection").dependent(:destroy) }
  it { is_expected.to have_many(:selected_invoice_custom_sections).through(:applied_invoice_custom_sections).source(:invoice_custom_section) }
  it { is_expected.to have_many(:manual_selected_invoice_custom_sections).through(:applied_invoice_custom_sections).source(:invoice_custom_section).conditions(section_type: :manual) }
  it { is_expected.to have_many(:system_generated_invoice_custom_sections).through(:applied_invoice_custom_sections).source(:invoice_custom_section).conditions(section_type: :system_generated) }

  describe "Clickhouse associations", clickhouse: true do
    it { is_expected.to have_many(:activity_logs).class_name("Clickhouse::ActivityLog") }
  end

  it "sets the default value to inherit" do
    expect(customer.finalize_zero_amount_invoice).to eq "inherit"
  end

  describe "validations" do
    subject(:customer) do
      described_class.new(organization:, external_id:)
    end

    let(:external_id) { SecureRandom.uuid }

    it "validates the language code" do
      customer.document_locale = nil
      expect(customer).to be_valid

      customer.document_locale = "en"
      expect(customer).to be_valid

      customer.document_locale = "foo"
      expect(customer).not_to be_valid

      customer.document_locale = ""
      expect(customer).not_to be_valid
    end

    it "validates the timezone" do
      expect(customer).to be_valid

      customer.timezone = "Europe/Paris"
      expect(customer).to be_valid

      customer.timezone = "foo"
      expect(customer).not_to be_valid

      customer.timezone = "America/Guadeloupe"
      expect(customer).not_to be_valid
    end

    describe "of email" do
      let(:customer) { build_stubbed(:customer, email: "invalid @example.com") }
      let(:error) { customer.errors.where(:email, :invalid_email_format) }

      context "when email is not changed" do
        it "does not add an error" do
          customer.valid?
          expect(error).not_to be_present
        end
      end

      context "when email is changed" do
        before do
          customer.email = email
          customer.valid?
        end

        context "when there is only one email" do
          context "when email is nil" do
            let(:email) { nil }

            it "does not add an error" do
              expect(error).not_to be_present
            end
          end

          context "when email is empty string" do
            let(:email) { "" }

            it "does not add an error" do
              expect(error).not_to be_present
            end
          end

          context "when email is valid" do
            let(:email) { "test@test-test.com" }

            it "does not add an error" do
              expect(error).not_to be_present
            end
          end

          context "when email is invalid" do
            let(:email) { "test@test- test.com" }

            it "adds an error" do
              expect(error).to be_present
            end
          end
        end

        context "when there are multiple comma-separated emails" do
          context "when emails are valid" do
            let(:email) { "test@test-test.com, test2@test.com" }

            it "does not add an error" do
              expect(error).not_to be_present
            end
          end

          context "when emails are not valid" do
            context "when one of the emails is blank" do
              let(:email) { "test@test- test.com, test2@test.com," }

              it "adds an error" do
                expect(error).to be_present
              end
            end

            context "when first one is invalid" do
              let(:email) { "test@test- test.com, test2@test.com" }

              it "adds an error" do
                expect(error).to be_present
              end
            end

            context "when second one is invalid" do
              let(:email) { "test@test-test.com, test2@te st.com" }

              it "adds an error" do
                expect(error).to be_present
              end
            end

            context "when both are invalid" do
              let(:email) { "test@test -test.com, test2@te st.com" }

              it "adds an error" do
                expect(error).to be_present
              end
            end
          end
        end
      end
    end

    describe "of country" do
      let(:customer) { build_stubbed(:customer, country:) }
      let(:error) { customer.errors.where(:country, :country_code_invalid) }

      before { customer.valid? }

      context "with non-null country value" do
        context "when value is a valid country code" do
          let(:country) { TZInfo::Country.all_codes.sample }

          it "does not add an error" do
            expect(error).not_to be_present
          end
        end

        context "when value is an invalid country code" do
          let(:country) { "USA" }

          it "adds an error" do
            expect(error).to be_present
          end
        end
      end

      context "with null country value" do
        let(:country) { nil }

        it "does not add an error" do
          expect(error).not_to be_present
        end
      end
    end

    describe "of shipping country" do
      let(:customer) { build_stubbed(:customer, shipping_country:) }
      let(:error) { customer.errors.where(:shipping_country, :country_code_invalid) }

      before { customer.valid? }

      context "with non-null shipping country value" do
        context "when value is a valid country code" do
          let(:shipping_country) { TZInfo::Country.all_codes.sample }

          it "does not add an error" do
            expect(error).not_to be_present
          end
        end

        context "when value is an invalid country code" do
          let(:shipping_country) { "USA" }

          it "adds an error" do
            expect(error).to be_present
          end
        end
      end

      context "with null shipping country value" do
        let(:shipping_country) { nil }

        it "does not add an error" do
          expect(error).not_to be_present
        end
      end
    end

    it { is_expected.to validate_inclusion_of(:customer_type).in_array(described_class::CUSTOMER_TYPES.keys) }
  end

  describe "#display_name" do
    subject(:customer) { build_stubbed(:customer, name:, legal_name:, firstname:, lastname:) }

    let(:name) { "ACME Inc" }
    let(:legal_name) { "ACME International Corporation" }
    let(:firstname) { "Thomas" }
    let(:lastname) { "Anderson" }

    context "when all fields are nil" do
      let(:name) { nil }
      let(:legal_name) { nil }
      let(:firstname) { nil }
      let(:lastname) { nil }

      it "returns an empty string" do
        expect(customer.display_name).to eq("")
      end
    end

    context "when name and legal_name are nil" do
      let(:name) { nil }
      let(:legal_name) { nil }

      it "returns only firstname and lastname if present" do
        expect(customer.display_name).to eq("Thomas Anderson")
      end
    end

    context "when firstname and lastname are nil" do
      let(:firstname) { nil }
      let(:lastname) { nil }

      it "returns only the legal_name" do
        expect(customer.display_name).to eq("ACME International Corporation")
      end

      context "when we dont have a legal_name" do
        let(:legal_name) { nil }

        it "returns only the name if present" do
          expect(customer.display_name).to eq("ACME Inc")
        end
      end
    end

    context "when name is present and both firstname and lastname are present" do
      let(:legal_name) { nil }

      it "returns name with firstname and lastname" do
        aggregate_failures do
          expect(customer.display_name).to eq("ACME Inc - Thomas Anderson")
          expect(customer.display_name(prefer_legal_name: false)).to eq("ACME Inc - Thomas Anderson")
        end
      end
    end

    context "when legal_name is present and both firstname and lastname are present" do
      let(:name) { nil }

      it "returns legal_name with firstname and lastname" do
        aggregate_failures do
          expect(customer.display_name).to eq("ACME International Corporation - Thomas Anderson")
          expect(customer.display_name(prefer_legal_name: false)).to eq("Thomas Anderson")
        end
      end
    end

    context "when all fields are present" do
      it "returns display name" do
        aggregate_failures do
          expect(customer.display_name).to eq("ACME International Corporation - Thomas Anderson")
          expect(customer.display_name(prefer_legal_name: false)).to eq("ACME Inc - Thomas Anderson")
        end
      end
    end
  end

  describe "customer_type enum" do
    subject(:customer) { build_stubbed(:customer, customer_type:) }

    context "when customer_type is company" do
      let(:customer_type) { "company" }

      it "identifies the customer as a company" do
        expect(customer.customer_type).to eq("company")
        expect(customer.customer_type_company?).to be true
      end
    end

    context "when customer_type is individual" do
      let(:customer_type) { "individual" }

      it "identifies the customer as an individual" do
        expect(customer.customer_type).to eq("individual")
        expect(customer.customer_type_individual?).to be true
      end
    end

    context "when customer_type is nil" do
      subject(:customer) { build(:customer) }

      it "defaults to nil for existing customers" do
        expect(customer.customer_type).to be_nil
      end
    end
  end

  describe "account_type enum" do
    subject(:customer) { build_stubbed(:customer, account_type:) }

    context "when account_type is customer" do
      let(:account_type) { "customer" }

      it "identifies the customer as a customer" do
        expect(customer.account_type).to eq("customer")
        expect(customer).to be_customer_account
      end
    end

    context "when account_type is partner" do
      let(:account_type) { "partner" }

      it "identifies the customer as partner" do
        expect(customer.account_type).to eq("partner")
        expect(customer).to be_partner_account
      end
    end

    context "when account_type is nil" do
      subject(:customer) { build(:customer) }

      it "defaults to customer for existing customers" do
        expect(customer.account_type).to eq "customer"
      end
    end
  end

  describe "preferred_document_locale" do
    subject(:preferred_document_locale) { customer.preferred_document_locale }

    let(:customer) do
      described_class.new(
        organization:,
        billing_entity:,
        document_locale: "en"
      )
    end

    it "returns the customer document_locale" do
      expect(preferred_document_locale).to eq(:en)
    end

    context "when customer does not have a document_locale" do
      before do
        customer.document_locale = nil
        billing_entity.document_locale = "fr"
      end

      it "returns the billing_entity document_locale" do
        expect(customer.preferred_document_locale).to eq(:fr)
      end
    end
  end

  describe "#editable?" do
    subject(:editable) { customer.editable? }

    context "when customer has a wallet" do
      let(:customer) { wallet.customer }
      let(:wallet) { create(:wallet) }

      it "returns false" do
        expect(editable).to eq(false)
      end
    end

    context "when customer has a coupon applied" do
      let(:customer) { applied_coupon.customer }
      let(:applied_coupon) { create(:applied_coupon) }

      it "returns false" do
        expect(editable).to eq(false)
      end
    end

    context "when customer has an addon applied" do
      let(:customer) { applied_add_on.customer }
      let(:applied_add_on) { create(:applied_add_on) }

      it "returns false" do
        expect(editable).to eq(false)
      end
    end

    context "when customer has an invoice" do
      let(:customer) { invoice.customer }
      let(:invoice) { create(:invoice) }

      it "returns false" do
        expect(editable).to eq(false)
      end
    end

    context "when customer has a subscription" do
      let(:customer) { subscription.customer }
      let(:subscription) { create(:subscription) }

      it "returns false" do
        expect(editable).to eq(false)
      end
    end

    context "when customer has no record that prevents editing" do
      it "returns true" do
        expect(editable).to eq(true)
      end
    end
  end

  describe "#provider_customer" do
    subject(:customer) { create(:customer, organization:, payment_provider:) }

    context "when payment provider is stripe" do
      let(:payment_provider) { "stripe" }
      let(:stripe_customer) { create(:stripe_customer, customer:) }

      before { stripe_customer }

      it "returns the stripe provider customer object" do
        expect(customer.provider_customer).to eq(stripe_customer)
      end
    end

    context "when payment provider is gocardless" do
      let(:payment_provider) { "gocardless" }
      let(:gocardless_customer) { create(:gocardless_customer, customer:) }

      before { gocardless_customer }

      it "returns the gocardless provider customer object" do
        expect(customer.provider_customer).to eq(gocardless_customer)
      end
    end
  end

  describe "#applicable_timezone" do
    subject(:customer) do
      described_class.new(billing_entity:, timezone: "Europe/Paris")
    end

    it "returns the customer timezone" do
      expect(customer.applicable_timezone).to eq("Europe/Paris")
    end

    context "when customer does not have a timezone" do
      let(:billing_entity_timezone) { "Europe/London" }

      before do
        customer.timezone = nil
        billing_entity.timezone = billing_entity_timezone
      end

      it "returns the billing entity timezone" do
        expect(customer.applicable_timezone).to eq("Europe/London")
      end

      context "when billing entity timezone is nil" do
        let(:billing_entity_timezone) { nil }

        it "returns the default timezone" do
          expect(customer.applicable_timezone).to eq("UTC")
        end
      end
    end
  end

  describe "#applicable_invoice_grace_period" do
    subject(:customer) do
      described_class.new(billing_entity:, invoice_grace_period: 3)
    end

    it "returns the customer invoice_grace_period" do
      expect(customer.applicable_invoice_grace_period).to eq(3)
    end

    context "when customer does not have an invoice grace period" do
      let(:billing_entity_invoice_grace_period) { 5 }

      before do
        customer.invoice_grace_period = nil
        billing_entity.invoice_grace_period = billing_entity_invoice_grace_period
      end

      it "returns the billing entity invoice_grace_period" do
        expect(customer.applicable_invoice_grace_period).to eq(5)
      end

      context "when billing entity invoice_grace_period is nil" do
        let(:billing_entity_invoice_grace_period) { nil }

        it "returns the default invoice_grace_period" do
          expect(customer.applicable_invoice_grace_period).to eq(0)
        end
      end
    end
  end

  describe "#applicable_net_payment_term" do
    subject(:applicable_net_payment_term) { customer.applicable_net_payment_term }

    let(:customer) do
      described_class.new(organization:, billing_entity:, net_payment_term: 15)
    end

    it "returns the customer net_payment_term" do
      expect(applicable_net_payment_term).to eq(15)
    end

    context "when customer does not have a net payment term" do
      let(:billing_entity_net_payment_term) { 30 }

      before do
        customer.net_payment_term = nil
        billing_entity.net_payment_term = billing_entity_net_payment_term
      end

      it "returns the billing entity net payment term" do
        expect(applicable_net_payment_term).to eq(billing_entity_net_payment_term)
      end

      context "when billing entity net_payment_term is nil" do
        let(:billing_entity_net_payment_term) { nil }

        it { is_expected.to be_nil }
      end
    end
  end

  describe "scoped selected_invoice_custom_sections" do
    let(:organization) { customer.organization }
    let(:manual_section) { create(:invoice_custom_section, organization:, section_type: :manual) }
    let(:system_generated_section) { create(:invoice_custom_section, organization:, section_type: :system_generated) }
    let(:customer_applied_manual_section) { create(:customer_applied_invoice_custom_section, customer:, invoice_custom_section: manual_section) }
    let(:customer_applied_system_generated_section) { create(:customer_applied_invoice_custom_section, customer:, invoice_custom_section: system_generated_section) }

    before do
      customer_applied_manual_section
      customer_applied_system_generated_section
    end

    it "returns the correct sections for each scoped association" do
      expect(customer.manual_selected_invoice_custom_sections).to contain_exactly(manual_section)
      expect(customer.system_generated_invoice_custom_sections).to contain_exactly(system_generated_section)
    end
  end

  describe "#applicable_invoice_custom_sections" do
    let(:organization) { customer.organization }
    let(:billing_entity) { customer.billing_entity }

    let(:manual_customer_section) do
      create(:invoice_custom_section, organization:, section_type: :manual, name: "Customer Section")
    end

    let(:manual_billing_entity_section) do
      create(:invoice_custom_section, organization:, section_type: :manual, name: "Billing Entity Section")
    end

    let(:system_generated_section) do
      create(:invoice_custom_section, organization:, section_type: :system_generated, name: "System Section")
    end

    context "when skip_invoice_custom_sections is true and there are system sections" do
      before do
        customer.update!(skip_invoice_custom_sections: true)
        create(:customer_applied_invoice_custom_section, customer:, organization:, billing_entity:, invoice_custom_section: system_generated_section)
      end

      it "returns only system generated sections" do
        expect(customer.applicable_invoice_custom_sections).to contain_exactly(system_generated_section)
      end
    end

    context "when customer has manual and system sections" do
      before do
        create(:customer_applied_invoice_custom_section, customer:, organization:, billing_entity:, invoice_custom_section: manual_customer_section)
        create(:customer_applied_invoice_custom_section, customer:, organization:, billing_entity:, invoice_custom_section: system_generated_section)
      end

      it "returns both manual and system generated sections" do
        expect(customer.applicable_invoice_custom_sections).to contain_exactly(manual_customer_section, system_generated_section)
      end
    end

    context "when customer has no manual, but billing entity has manual, and customer has system" do
      before do
        create(:billing_entity_applied_invoice_custom_section, organization:, billing_entity:, invoice_custom_section: manual_billing_entity_section)
        create(:customer_applied_invoice_custom_section, customer:, organization:, billing_entity:, invoice_custom_section: system_generated_section)
      end

      it "returns billing entity manual + system sections" do
        expect(customer.applicable_invoice_custom_sections).to contain_exactly(manual_billing_entity_section, system_generated_section)
      end
    end

    context "when only billing entity has manual sections and no system sections" do
      before do
        create(:billing_entity_applied_invoice_custom_section, organization:, billing_entity:, invoice_custom_section: manual_billing_entity_section)
      end

      it "returns only billing entity manual sections" do
        expect(customer.applicable_invoice_custom_sections).to contain_exactly(manual_billing_entity_section)
      end
    end

    context "when only system_generated sections exist" do
      before do
        create(:customer_applied_invoice_custom_section, customer:, organization:, billing_entity:, invoice_custom_section: system_generated_section)
      end

      it "returns only system_generated sections" do
        expect(customer.applicable_invoice_custom_sections).to contain_exactly(system_generated_section)
      end
    end

    context "when no manual or system_generated sections are selected" do
      it "returns an empty collection" do
        expect(customer.applicable_invoice_custom_sections).to be_empty
      end
    end
  end

  describe "#configurable_invoice_custom_sections" do
    let(:organization) { customer.organization }
    let(:billing_entity) { customer.billing_entity }
    let(:invoice_custom_section_a) { create(:invoice_custom_section, organization:) }
    let(:invoice_custom_section_b) { create(:invoice_custom_section, organization:) }

    before do
      invoice_custom_section_a
      invoice_custom_section_b
    end

    context "when customer has skip_invoice_custom_sections set to true" do
      before do
        customer.update!(skip_invoice_custom_sections: true)
        create(:billing_entity_applied_invoice_custom_section, billing_entity:, invoice_custom_section: invoice_custom_section_a)
      end

      it "returns an empty collection" do
        expect(customer.configurable_invoice_custom_sections).to be_empty
      end
    end

    context "when customer has its own applied_invoice_custom_sections" do
      before do
        create(:customer_applied_invoice_custom_section, customer:, invoice_custom_section: invoice_custom_section_b)
      end

      it "returns the customer's selected_invoice_custom_sections" do
        expect(customer.configurable_invoice_custom_sections).to contain_exactly(invoice_custom_section_b)
      end
    end

    context "when customer does not have any applied_invoice_custom_sections but billing entity has" do
      before do
        create(:billing_entity_applied_invoice_custom_section, billing_entity:, invoice_custom_section: invoice_custom_section_a)
      end

      it "returns the billing entity's invoice_custom_sections" do
        expect(customer.configurable_invoice_custom_sections).to contain_exactly(invoice_custom_section_a)
      end
    end

    context "when neither customer nor billing entity have selected invoice custom sections" do
      it "returns an empty collection" do
        expect(customer.configurable_invoice_custom_sections).to be_empty
      end
    end
  end

  describe "timezones" do
    subject(:customer) do
      build(
        :customer,
        organization:,
        timezone: "Europe/Paris",
        created_at: DateTime.parse("2022-11-17 23:34:23")
      )
    end

    let(:organization) { create(:organization) }

    before do
      organization.default_billing_entity.update(timezone: "America/Los_Angeles")
    end

    it "has helper to get dates in timezones" do
      expect(customer.created_at.to_s).to eq("2022-11-17 23:34:23 UTC")
      expect(customer.created_at_in_customer_timezone.to_s).to eq("2022-11-18 00:34:23 +0100")
      expect(customer.created_at_in_organization_timezone.to_s).to eq("2022-11-17 15:34:23 -0800")
      expect(customer.created_at_in_billing_entity_timezone.to_s).to eq("2022-11-17 15:34:23 -0800")
    end
  end

  describe "slug" do
    let(:organization) { create(:organization, name: "LAGO") }

    let(:customer) do
      build(:customer, organization:)
    end

    it "assigns a sequential id and a slug to a new customer" do
      customer.save
      organization_id_substring = organization.id.last(4).upcase

      aggregate_failures do
        expect(customer).to be_valid
        expect(customer.sequential_id).to eq(1)
        expect(customer.slug).to eq("LAG-#{organization_id_substring}-001")
      end
    end

    context "with custom document_number_prefix" do
      let(:organization) { create(:organization, name: "LAGO") }

      before do
        create(:customer, organization:, sequential_id: 5)
        organization.update!(document_number_prefix: "ORG-55")
      end

      it "assigns a sequential id and a slug to a new customer" do
        customer.save

        aggregate_failures do
          expect(customer).to be_valid
          expect(customer.sequential_id).to eq(6)
          expect(customer.slug).to eq("ORG-55-006")
        end
      end
    end
  end

  describe "#same_billing_and_shipping_address?" do
    subject(:method_call) { customer.same_billing_and_shipping_address? }

    context "when shipping address is present" do
      context "when shipping address is not the same as billing address" do
        let(:customer) { build_stubbed(:customer, :with_shipping_address) }

        it "returns false" do
          expect(subject).to be(false)
        end
      end

      context "when shipping address is the same as billing address" do
        let(:customer) { build_stubbed(:customer, :with_same_billing_and_shipping_address) }

        it "returns true" do
          expect(subject).to be(true)
        end
      end
    end

    context "when shipping address is not present" do
      let(:customer) { build_stubbed(:customer) }

      it "returns true" do
        expect(subject).to be(true)
      end
    end
  end

  describe "#empty_billing_and_shipping_address?" do
    subject(:method_call) { customer.empty_billing_and_shipping_address? }

    context "when shipping address is present" do
      context "when billing address is present" do
        let(:customer) { build_stubbed(:customer, :with_shipping_address) }

        it "returns false" do
          expect(subject).to be(false)
        end
      end

      context "when billing address is not present" do
        let(:customer) do
          build_stubbed(
            :customer,
            :with_shipping_address,
            address_line1: nil,
            address_line2: nil,
            city: nil,
            zipcode: nil,
            state: nil,
            country: nil
          )
        end

        it "returns false" do
          expect(subject).to be(false)
        end
      end
    end

    context "when shipping address is not present" do
      context "when billing address is present" do
        let(:customer) { build_stubbed(:customer) }

        it "returns false" do
          expect(subject).to be(false)
        end
      end

      context "when billing address is not present" do
        let(:customer) do
          build_stubbed(
            :customer,
            address_line1: nil,
            address_line2: nil,
            city: nil,
            zipcode: nil,
            state: nil,
            country: nil
          )
        end

        it "returns true" do
          expect(subject).to be(true)
        end
      end
    end
  end

  describe "#overdue_balance_cents" do
    subject(:overdue_balance_cents) { customer.overdue_balance_cents }

    let(:customer) { create(:customer, currency: "USD") }

    context "when there are no overdue invoices" do
      before do
        create(:invoice, customer: customer, payment_overdue: false, currency: "USD", total_amount_cents: 5_00)
      end

      it { is_expected.to be_zero }
    end

    context "when there are overdue invoices in the customer's currency" do
      before do
        create(:invoice, customer: customer, payment_overdue: true, currency: "USD", total_amount_cents: 2_00)
        create(:invoice, customer: customer, payment_overdue: true, currency: "USD", total_amount_cents: 3_00)
      end

      it { is_expected.to eq 5_00 }
    end

    context "when there are overdue invoices in a different currency" do
      before do
        create(:invoice, customer: customer, payment_overdue: true, currency: "USD", total_amount_cents: 4_00)
        create(:invoice, customer: customer, payment_overdue: true, currency: "EUR", total_amount_cents: 3_00)
      end

      it "ignores invoices in other currencies" do
        expect(customer.overdue_balance_cents).to eq 4_00
      end
    end

    context "when there are both overdue and non-overdue invoices" do
      before do
        create(:invoice, customer: customer, payment_overdue: true, currency: "USD", total_amount_cents: 2_00)
        create(:invoice, customer: customer, payment_overdue: false, currency: "USD", total_amount_cents: 1_00)
      end

      it "only sums the overdue invoices" do
        expect(customer.overdue_balance_cents).to eq 2_00
      end
    end

    context "when invoices are self billed" do
      before do
        create(:invoice, customer: customer, payment_overdue: true, currency: "USD", total_amount_cents: 2_00)
        create(:invoice, :self_billed, customer: customer, payment_overdue: true, currency: "USD", total_amount_cents: 3_00)
      end

      it "ignores self billed invoices" do
        expect(customer.overdue_balance_cents).to eq 2_00
      end
    end
  end

  describe "#reset_dunning_campaign!" do
    let(:customer) do
      create(
        :customer,
        last_dunning_campaign_attempt: 5,
        last_dunning_campaign_attempt_at: 1.day.ago
      )
    end

    it "changes dunning campaign status counters" do
      expect { customer.reset_dunning_campaign! && customer.reload }
        .to change(customer, :last_dunning_campaign_attempt).to(0)
        .and change(customer, :last_dunning_campaign_attempt_at).to(nil)
    end
  end

  describe "#flag_wallets_for_refresh" do
    context "without any wallets" do
      it "returns 0" do
        expect(customer.flag_wallets_for_refresh).to be_zero
      end
    end

    context "without active wallets" do
      it "does not flag wallets for refresh" do
        wallet = create(:wallet, :terminated, customer:)

        expect { customer.flag_wallets_for_refresh }.not_to change {
          wallet.reload.ready_to_be_refreshed
        }.from(false)
      end
    end

    it "flags all active wallets for refresh" do
      wallet = create(:wallet, customer:)

      expect { customer.flag_wallets_for_refresh }.to change {
        wallet.reload.ready_to_be_refreshed
      }.from(false).to(true)
    end
  end

  describe "#tax_customer" do
    let(:customer) { create(:customer) }

    context "with anrok attached" do
      let(:anrok_customer) { create(:anrok_customer, customer:) }

      before { anrok_customer }

      it "returns anrok customer" do
        expect(customer.tax_customer).to eq(anrok_customer)
      end
    end

    context "with avalara attached" do
      let(:avalara_customer) { create(:avalara_customer, customer:) }

      before { avalara_customer }

      it "returns avalara customer" do
        expect(customer.tax_customer).to eq(avalara_customer)
      end
    end

    context "without any tax integration" do
      it "returns nil" do
        expect(customer.tax_customer).to eq(nil)
      end
    end
  end
end
