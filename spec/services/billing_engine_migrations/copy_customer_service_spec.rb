# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingEngineMigrations::CopyCustomerService do
  subject(:result) { described_class.call(migration:, customer:) }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:shadow_organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let_it_be(:billing_entity) { organization.default_billing_entity }

  let(:shadow_entity_code) { billing_entity.code }
  let(:migration) { create(:billing_engine_migration, organization:, shadow_organization:) }

  let(:customer) do
    create(:customer, :with_shipping_address, organization:, billing_entity:, timezone: "America/Los_Angeles")
  end

  before { create(:billing_entity, organization: shadow_organization, code: shadow_entity_code) }

  it "creates the customer in the shadow organization with the allow-listed attributes" do
    expect { result }.to change { shadow_organization.customers.count }.by(1)

    expect(result).to be_success
    expect(result.customer).to have_attributes(
      organization: shadow_organization,
      external_id: customer.external_id,
      name: customer.name,
      firstname: customer.firstname,
      lastname: customer.lastname,
      email: customer.email,
      phone: customer.phone,
      url: customer.url,
      legal_name: customer.legal_name,
      legal_number: customer.legal_number,
      tax_identification_number: customer.tax_identification_number,
      address_line1: customer.address_line1,
      address_line2: customer.address_line2,
      city: customer.city,
      state: customer.state,
      zipcode: customer.zipcode,
      country: customer.country,
      currency: customer.currency,
      shipping_address_line1: customer.shipping_address_line1,
      shipping_address_line2: customer.shipping_address_line2,
      shipping_city: customer.shipping_city,
      shipping_state: customer.shipping_state,
      shipping_zipcode: customer.shipping_zipcode,
      shipping_country: customer.shipping_country
    )
    expect(result.customer.billing_entity.code).to eq(billing_entity.code)
  end

  context "when the customer has a payment provider, metadata and taxes" do
    let(:customer) { create(:customer, :with_stripe_payment_provider, organization:, billing_entity:) }

    before do
      create(:customer_metadata, customer:)
      create(:customer_applied_tax, customer:, tax: create(:tax, organization:))
    end

    it "does not copy them" do
      expect(result.customer.payment_provider).to be_nil
      expect(result.customer.payment_provider_code).to be_nil
      expect(result.customer.payment_provider_customers).to be_empty
      expect(result.customer.metadata).to be_empty
      expect(result.customer.taxes).to be_empty
    end
  end

  context "when the shadow organization already has the customer" do
    let(:shadow_customer) { create(:customer, organization: shadow_organization, external_id: customer.external_id) }

    before { shadow_customer }

    it "returns it without creating another one" do
      expect { result }.not_to change { shadow_organization.customers.count }

      expect(result.customer).to eq(shadow_customer)
    end
  end

  context "when the customer timezone is inherited from its billing entity", :premium do
    let(:paris_entity) { create(:billing_entity, organization:, timezone: "Europe/Paris") }
    let(:shadow_entity_code) { paris_entity.code }
    let(:customer) { create(:customer, organization:, billing_entity: paris_entity, timezone: nil) }

    it "gives the shadow customer the same timezone" do
      expect(result.customer.applicable_timezone).to eq("Europe/Paris")
    end
  end

  context "when the customer is created concurrently" do
    let(:taken_failure) do
      BaseService::Result.new.single_validation_failure!(field: :external_id, error_code: "value_already_exist")
    end

    let(:concurrent_customer) do
      create(:customer, organization: shadow_organization, external_id: customer.external_id)
    end

    before do
      allow(Customers::CreateService).to receive(:call) do
        concurrent_customer
        taken_failure
      end
    end

    it "returns the customer created by the other writer" do
      expect(result).to be_success
      expect(result.customer).to eq(concurrent_customer)
    end
  end

  context "when the external id is reported as taken but no shadow customer has it" do
    before do
      allow(Customers::CreateService).to receive(:call).and_return(
        BaseService::Result.new.single_validation_failure!(field: :external_id, error_code: "value_already_exist")
      )
    end

    it "returns the failure" do
      expect(result).to be_failure
      expect(result.error.messages).to eq(external_id: ["value_already_exist"])
      expect(result.customer).to be_nil
    end
  end

  context "when the customer creation fails for another reason" do
    before do
      allow(Customers::CreateService).to receive(:call).and_return(
        BaseService::Result.new.single_validation_failure!(field: :external_id, error_code: "value_is_invalid")
      )
    end

    it "returns the failure" do
      expect(result).to be_failure
      expect(result.error.messages).to eq(external_id: ["value_is_invalid"])
    end
  end

  context "when the migration is not shadowing" do
    let(:migration) { create(:billing_engine_migration, organization:, shadow_organization:, status: "paused") }

    it "does nothing" do
      expect { result }.not_to change { shadow_organization.customers.count }

      expect(result).to be_success
      expect(result.customer).to be_nil
    end
  end

  context "when the customer belongs to another organization" do
    let(:customer) { create(:customer, organization: create(:organization)) }

    it "does nothing" do
      expect { result }.not_to change { shadow_organization.customers.count }

      expect(result).to be_success
      expect(result.customer).to be_nil
    end
  end

  context "when the shadow organization has no billing entity with the code of the customer" do
    let(:shadow_entity_code) { "unknown_entity" }

    it "returns the failure and creates nothing" do
      expect { result }.not_to change { shadow_organization.customers.count }

      expect(result).to be_failure
      expect(result.customer).to be_nil
    end
  end
end
